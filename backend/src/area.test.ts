import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { destination, normalizeRing, polygonAreaSqm, splitThaiArea, tonsPerRai } from "./area";

describe("thai area", () => {
  it("splits one rai", () => {
    assert.deepEqual(splitThaiArea(1600), { rai: 1, ngan: 0, wa: 0, raiDecimal: 1 });
  });

  it("splits one rai and one ngan", () => {
    assert.deepEqual(splitThaiArea(2000), { rai: 1, ngan: 1, wa: 0, raiDecimal: 1.25 });
  });

  it("splits one extra square wa", () => {
    assert.deepEqual(splitThaiArea(1604), { rai: 1, ngan: 0, wa: 1, raiDecimal: 1604 / 1600 });
  });
});

describe("polygon", () => {
  it("measures a 100 by 200 metre rectangle", () => {
    const origin = { latitude: 14.47, longitude: 100.12 };
    const points = [
      origin,
      destination(origin, 0, 200),
      destination(origin, 100, 200),
      destination(origin, 100, 0),
    ];
    const area = polygonAreaSqm(points);
    assert.ok(Math.abs(area - 20000) / 20000 < 0.01, `area was ${area}`);
  });

  it("drops a repeated closing corner", () => {
    const ring = normalizeRing([
      { latitude: 1, longitude: 2 },
      { latitude: 3, longitude: 4 },
      { latitude: 5, longitude: 6 },
      { latitude: 1, longitude: 2 },
    ]);
    assert.equal(ring.length, 3);
  });
});

describe("yield rate", () => {
  it("divides tons by rai", () => {
    assert.equal(tonsPerRai(150, 16000), 15);
    assert.equal(tonsPerRai(10, 0), null);
  });
});
