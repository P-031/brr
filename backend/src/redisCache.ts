import Redis from "ioredis";

const redis = new Redis(process.env.REDIS_URL ?? "redis://127.0.0.1:6379");

export async function getOrSet<T>(key: string, load: () => Promise<T>, ttlMs = 60): Promise<T> {
    const hit = await redis.get(key);
    if (hit) return JSON.parse(hit) as T;
    const value = await load();
    await redis.set(key, JSON.stringify(value), "EX", ttlMs);
    return value;
}

export async function invalidate(key: string) {
    await redis.del(key);
}