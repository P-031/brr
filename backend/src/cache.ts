type Entry<T> = { value: T; expiresAt: number };

export class TtlCache {
    private readonly store = new Map<string, Entry<unknown>>();
    constructor(private readonly defaultTtlMs: number) {}

    get<T>(key: string): T | undefined {
        const row = this.store.get(key);
        if (!row) return undefined;
        if (Date.now() >= row.expiresAt) {
            this.store.delete(key);
            return undefined;
        }
        return row.value as T;
    }

    set<T>(key: string, value: T, ttlMs = this.defaultTtlMs) {
        this.store.set(key, { value, expiresAt: Date.now() + ttlMs });
    }

    async getOrSet<T>(key: string, load: () => Promise<T>, ttlMs = this.defaultTtlMs): Promise<T> {
        const hit = this.get<T>(key);
        if (hit !== undefined) return hit;
        const value = await load();
        this.set(key, value, ttlMs);
        return value;
    }

    delete(key: string): void {
        this.store.delete(key);
    }
}

export const metaListCache = new TtlCache(60_000);