import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { destination, type LatLng } from "./area";
import type { OverlapRow } from "./boundary";
import { HttpError } from "./http";
import { blockingOverlaps } from "./overlap";
import { firstCrossingEdge, measureSurvey, type Survey } from "./survey";

const origin = { latitude: 14.47, longitude: 100.12 };
const start = new Date("2026-11-10T01:00:00.000Z");
const now = new Date("2026-11-10T03:00:00.000Z");

/** Walks the points one minute apart, 5 m GPS accuracy. */
function walk(points: LatLng[], minutesApart = 1): Survey {
  const corners = points.map((point, index) => ({
    ...point,
    accuracyM: 5,
    capturedAt: new Date(start.getTime() + (index + 1) * minutesApart * 60_000),
  }));
  return {
    startedAt: start,
    finishedAt: new Date(start.getTime() + (points.length + 1) * minutesApart * 60_000),
    corners,
  };
}

/** 100 m north by 50 m east. */
const field = [
  origin,
  destination(origin, 0, 50),
  destination(origin, 100, 50),
  destination(origin, 100, 0),
];

function rejectsCorner(survey: Survey, corner?: number) {
  assert.throws(
    () => measureSurvey(survey, now),
    (error: unknown) =>
      error instanceof HttpError &&
      error.status === 400 &&
      error.extra.code === "SURVEY_INVALID" &&
      (corner === undefined || error.extra.corner === corner),
  );
}

describe("walked survey", () => {
  it("measures a walked rectangle", () => {
    const measured = measureSurvey(walk(field), now);
    assert.equal(measured.ring.length, 4);
    assert.ok(Math.abs(measured.areaSqm - 5000) / 5000 < 0.01, `area was ${measured.areaSqm}`);
  });

  it("drops a last corner that returns to the first", () => {
    const measured = measureSurvey(walk([...field, destination(origin, 0.5, 0.5)]), now);
    assert.equal(measured.ring.length, 4);
  });

  it("rejects a corner with poor GPS", () => {
    const survey = walk(field);
    survey.corners[2].accuracyM = 40;
    rejectsCorner(survey, 3);
  });

  it("rejects a corner reached faster than walking", () => {
    rejectsCorner(walk(field, 0.1), 2);
  });

  it("rejects corners out of time order", () => {
    const survey = walk(field);
    survey.corners[1].capturedAt = new Date(survey.corners[0].capturedAt.getTime() - 1000);
    rejectsCorner(survey);
  });

  it("rejects a double tap on the same corner", () => {
    rejectsCorner(walk([field[0], field[1], destination(field[1], 0.5, 0), field[2], field[3]]), 3);
  });

  it("rejects a walk that finishes in the future", () => {
    const survey = walk(field);
    rejectsCorner({ ...survey, finishedAt: new Date(now.getTime() + 60 * 60_000) });
  });

  it("rejects a tiny plot", () => {
    rejectsCorner(walk([origin, destination(origin, 0, 5), destination(origin, 5, 5), destination(origin, 5, 0)]));
  });

  it("rejects an outline that crosses itself", () => {
    const bowtie = [field[0], field[2], field[1], field[3]];
    assert.notEqual(firstCrossingEdge(bowtie), -1);
    rejectsCorner(walk(bowtie));
  });
});

describe("overlap", () => {
  const row = (overlapSqm: number, farmerId = "farmer-2"): OverlapRow => ({
    id: "plot-2",
    name: "แปลงข้างบ้าน",
    farmerId,
    areaSqm: 10_000,
    overlapSqm,
  });

  it("allows a thin sliver along a shared border", () => {
    assert.deepEqual(blockingOverlaps([row(40), row(240)], 5000, "farmer-1"), []);
  });

  it("blocks a real overlap and hides the other farmer's plot", () => {
    const [conflict] = blockingOverlaps([row(1000)], 5000, "farmer-1");
    assert.deepEqual(conflict, { own: false, overlapSqm: 1000, overlapPercent: 20 });
  });

  it("names the farmer's own plot", () => {
    const [conflict] = blockingOverlaps([row(5000, "farmer-1")], 5000, "farmer-1");
    assert.equal(conflict.plotId, "plot-2");
    assert.equal(conflict.overlapPercent, 100);
  });
});
