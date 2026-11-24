import { earthRadiusM, polygonAreaSqm, ringCenter, type LatLng } from "./area";
import { HttpError } from "./http";

/** Shared with the app so it can check a walk before it is ever online. */
export const surveyRules = {
  minCorners: 3,
  maxCorners: 500,
  /** Worst GPS accuracy (metres, as the phone reports it) accepted for a corner. */
  maxAccuracyM: 15,
  /** Corners closer than this to the previous one count as a double tap. */
  minCornerGapM: 2,
  /** Faster than a brisk walk between corners means the corner was not walked to. */
  maxWalkSpeedMps: 3,
  maxDurationHours: 12,
  /** How far ahead of the server clock a phone clock may run. */
  maxClockSkewMinutes: 5,
  minAreaSqm: 100,
  /** Two plots may overlap by up to max(overlapMinSqm, overlapMaxShare of the smaller plot). */
  overlapMinSqm: 50,
  overlapMaxShare: 0.05,
} as const;

export type Corner = LatLng & {
  accuracyM: number;
  capturedAt: Date;
};

export type Survey = {
  startedAt: Date;
  finishedAt: Date;
  corners: Corner[];
};

export type MeasuredSurvey = {
  ring: LatLng[];
  corners: Corner[];
  areaSqm: number;
  center: LatLng;
};

function invalid(message: string, corner?: number): never {
  throw new HttpError(400, message, { code: "SURVEY_INVALID", ...(corner === undefined ? {} : { corner }) });
}

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

export function distanceM(a: LatLng, b: LatLng): number {
  const dLat = toRadians(b.latitude - a.latitude);
  const dLng = toRadians(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(a.latitude)) * Math.cos(toRadians(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * earthRadiusM * Math.asin(Math.min(1, Math.sqrt(h)));
}

type Xy = { x: number; y: number };

function flatten(points: LatLng[]): Xy[] {
  const lat0 = points.reduce((sum, point) => sum + point.latitude, 0) / points.length;
  const cosLat = Math.cos(toRadians(lat0));
  return points.map((point) => ({
    x: toRadians(point.longitude) * earthRadiusM * cosLat,
    y: toRadians(point.latitude) * earthRadiusM,
  }));
}

function turn(a: Xy, b: Xy, c: Xy): number {
  return Math.sign((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x));
}

function onSegment(a: Xy, b: Xy, p: Xy): boolean {
  return (
    Math.min(a.x, b.x) <= p.x && p.x <= Math.max(a.x, b.x) && Math.min(a.y, b.y) <= p.y && p.y <= Math.max(a.y, b.y)
  );
}

function segmentsTouch(a: Xy, b: Xy, c: Xy, d: Xy): boolean {
  const t1 = turn(a, b, c);
  const t2 = turn(a, b, d);
  const t3 = turn(c, d, a);
  const t4 = turn(c, d, b);
  if (t1 !== t2 && t3 !== t4) return true;
  return (
    (t1 === 0 && onSegment(a, b, c)) ||
    (t2 === 0 && onSegment(a, b, d)) ||
    (t3 === 0 && onSegment(c, d, a)) ||
    (t4 === 0 && onSegment(c, d, b))
  );
}

/** Index of the first edge that crosses a non-neighbouring edge, or -1 when the outline is simple. */
export function firstCrossingEdge(ring: LatLng[]): number {
  const xy = flatten(ring);
  const n = xy.length;
  for (let i = 0; i < n; i += 1) {
    for (let j = i + 2; j < n; j += 1) {
      if (i === 0 && j === n - 1) continue;
      if (segmentsTouch(xy[i], xy[(i + 1) % n], xy[j], xy[(j + 1) % n])) return i;
    }
  }
  return -1;
}

/** Checks a walked outline. Corner numbers in errors start at 1, in walking order. */
export function measureSurvey(survey: Survey, now: Date): MeasuredSurvey {
  const rules = surveyRules;
  const skewMs = rules.maxClockSkewMinutes * 60_000;
  const { startedAt, finishedAt } = survey;

  if (finishedAt < startedAt) invalid("เวลาจบการเดินต้องไม่ก่อนเวลาเริ่ม");
  if (finishedAt.getTime() - startedAt.getTime() > rules.maxDurationHours * 3_600_000) {
    invalid(`เดินวัดแปลงได้ไม่เกิน ${rules.maxDurationHours} ชั่วโมง`);
  }
  if (finishedAt.getTime() > now.getTime() + skewMs) invalid("เวลาในเครื่องเดินหน้าเกินจริง");

  let corners = survey.corners;
  if (corners.length >= 4 && distanceM(corners[0], corners[corners.length - 1]) < rules.minCornerGapM) {
    corners = corners.slice(0, -1);
  }
  if (corners.length < rules.minCorners) invalid(`ต้องเดินเก็บมุมอย่างน้อย ${rules.minCorners} มุม`);
  if (corners.length > rules.maxCorners) invalid(`เก็บมุมได้ไม่เกิน ${rules.maxCorners} มุม`);

  corners.forEach((corner, index) => {
    const number = index + 1;
    if (corner.accuracyM > rules.maxAccuracyM) {
      invalid(`มุมที่ ${number} GPS คลาดเคลื่อนเกิน ${rules.maxAccuracyM} เมตร`, number);
    }
    if (corner.capturedAt < startedAt || corner.capturedAt > finishedAt) {
      invalid(`มุมที่ ${number} ถูกเก็บนอกช่วงเวลาที่เดินวัด`, number);
    }
    if (index === 0) return;

    const previous = corners[index - 1];
    const seconds = (corner.capturedAt.getTime() - previous.capturedAt.getTime()) / 1000;
    if (seconds <= 0) invalid(`มุมที่ ${number} ต้องถูกเก็บหลังมุมก่อนหน้า`, number);

    const gap = distanceM(previous, corner);
    if (gap < rules.minCornerGapM) invalid(`มุมที่ ${number} ซ้ำกับมุมก่อนหน้า`, number);

    const walked = Math.max(0, gap - previous.accuracyM - corner.accuracyM);
    if (walked / seconds > rules.maxWalkSpeedMps) {
      invalid(`มุมที่ ${number} ไกลจากมุมก่อนหน้าเกินกว่าจะเดินถึงในเวลานั้น`, number);
    }
  });

  const ring = corners.map(({ latitude, longitude }) => ({ latitude, longitude }));
  const crossing = firstCrossingEdge(ring);
  if (crossing >= 0) invalid(`ขอบแปลงตัดกันเองที่ช่วงมุม ${crossing + 1}`, crossing + 1);

  const areaSqm = polygonAreaSqm(ring);
  if (areaSqm < rules.minAreaSqm) invalid(`แปลงต้องใหญ่อย่างน้อย ${rules.minAreaSqm} ตารางเมตร`);

  return { ring, corners, areaSqm, center: ringCenter(ring) };
}

/** Largest overlap still treated as GPS error along a shared border. */
export function allowedOverlapSqm(areaA: number, areaB: number): number {
  return Math.max(surveyRules.overlapMinSqm, surveyRules.overlapMaxShare * Math.min(areaA, areaB));
}
