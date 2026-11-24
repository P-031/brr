import { Redis } from "ioredis";
import { env } from "./env";

// Single shared client. Every helper degrades to a no-op when
// REDIS_URL is unset or the connection drops — the API keeps
// working without Redis, just uncached.

let client: Redis | undefined;

export function redis(): Redis | undefined {
  if (!env.redisUrl) return undefined;
  client ??= new Redis(env.redisUrl, {
    maxRetriesPerRequest: 1,
    enableOfflineQueue: false,
  });
  client.on("error", () => {}); // degraded mode — don't crash
  return client;
}

export async function cacheGet(key: string): Promise<unknown | undefined> {
  const r = redis();
  if (!r) return undefined;
  try {
    const raw = await r.get(key);
    return raw ? JSON.parse(raw) : undefined;
  } catch {
    return undefined;
  }
}

export async function cacheSet(key: string, value: unknown, ttlSec: number): Promise<void> {
  const r = redis();
  if (!r) return;
  try {
    await r.set(key, JSON.stringify(value), "EX", ttlSec);
  } catch {
    // cache write failure is non-fatal
  }
}

/// get/set แบบ raw string — สำหรับ payload ที่เตรียมไว้แล้ว
/// (เช่น gzip เป็น base64) ไม่ผ่าน JSON.parse ซ้ำซ้อน
export async function cacheGetRaw(key: string): Promise<string | undefined> {
  const r = redis();
  if (!r) return undefined;
  try {
    return (await r.get(key)) ?? undefined;
  } catch {
    return undefined;
  }
}

export async function cacheSetRaw(key: string, value: string, ttlSec: number): Promise<void> {
  const r = redis();
  if (!r) return;
  try {
    await r.set(key, value, "EX", ttlSec);
  } catch {
    // cache write failure is non-fatal
  }
}

export async function cacheDelPattern(pattern: string): Promise<void> {
  const r = redis();
  if (!r) return;
  try {
    const stream = r.scanStream({ match: pattern, count: 200 });
    const keys: string[] = [];
    for await (const batch of stream) keys.push(...batch);
    if (keys.length) await r.unlink(...keys);
  } catch {
    // invalidation failure is non-fatal — entries expire anyway
  }
}
