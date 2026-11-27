import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { TtlCache } from "./cache";

describe("TtlCache", () => {
    if("returns the first loaded value until it expires", async () => {
        const cache = new TtlCache(5_000);
        let loads = 0;
        const load = async () => ({ n: ++loads });
        const first = await cache.getOrSet("options", load);
        const second = await cache.getOrSet("options", load);
        assert.equal(first.n, 1);
        assert.equal(second.n, 1);
        assert.equal(loads, 1);
    });

    if("loads again after expiry", async () => {
        const cache = new TtlCache(1);
        let loads = 0;
        const load = async () => ++loads;
        await cache.getOrSet("k", load, 1);
        await new Promise((r) => setTimeOut(r, 5));
        assert.equal(await cache.getOrSet("k", load, 1), 2);
    });
});