import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { decodeCursor, encodeCursor } from "./cursor";
import { HttpError } from "./http";

describe("cursor", () => {
  it("round-trips the last row of a page", () => {
    const createdAt = new Date("2026-03-18T02:00:00.000Z");
    const decoded = decodeCursor(encodeCursor(createdAt, "plot_home"));
    assert.equal(decoded.id, "plot_home");
    assert.equal(decoded.createdAt.toISOString(), createdAt.toISOString());
  });

  it("rejects a broken cursor", () => {
    assert.throws(() => decodeCursor("not-a-cursor"), (error: unknown) => {
      return error instanceof HttpError && error.status === 400;
    });
  });
});
