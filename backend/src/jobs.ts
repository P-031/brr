import { Queue, Worker } from "bullmq";
import { env } from "./env";
import { redis } from "./redis";

// BullMQ on the same Redis — async domain events. Today the worker
// records each event into a per-user Redis list as the seed for an
// in-app notifications feed; heavier jobs (area recompute, report
// generation) can join the same queue later.

const QUEUE_NAME = "plot-events";
const MAX_EVENTS = 50;

let queue: Queue | undefined;

function connection() {
  if (!env.redisUrl) return undefined;
  const url = new URL(env.redisUrl);
  return { host: url.hostname, port: Number(url.port || 6379) };
}

function plotQueue(): Queue | undefined {
  const conn = connection();
  if (!conn) return undefined;
  queue ??= new Queue(QUEUE_NAME, { connection: conn });
  return queue;
}

/// Fire-and-forget — enqueue failures must never break the request.
export async function enqueuePlotEvent(
  type: string,
  payload: Record<string, unknown>,
): Promise<void> {
  try {
    await plotQueue()?.add(type, payload, { removeOnComplete: 100 });
  } catch {
    // queue unavailable — event is dropped, request still succeeds
  }
}

/// Starts the worker when Redis is configured. Called once from index.ts.
export function startWorker(): Worker | undefined {
  const conn = connection();
  if (!conn) return undefined;
  return new Worker(
    QUEUE_NAME,
    async (job) => {
      const r = redis();
      if (!r || typeof job.data.userId !== "string") return;
      const key = `notifications:${job.data.userId}`;
      const entry = JSON.stringify({ type: job.name, at: Date.now(), ...job.data });
      await r.multi().lpush(key, entry).ltrim(key, 0, MAX_EVENTS - 1).exec();
    },
    { connection: conn },
  );
}
