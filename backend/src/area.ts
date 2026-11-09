export const earthRadiusM = 6378137;
export const sqmPerRai = 1600;
export const sqmPerNgan = 400;
export const sqmPerWa = 4;

export type LatLng = {
  latitude: number;
  longitude: number;
};

export type ThaiArea = {
  rai: number;
  ngan: number;
  wa: number;
  raiDecimal: number;
};

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

function toDegrees(radians: number): number {
  return (radians * 180) / Math.PI;
}

export function destination(origin: LatLng, northM: number, eastM: number): LatLng {
  const latitude = origin.latitude + toDegrees(northM / earthRadiusM);
  const longitude =
    origin.longitude + toDegrees(eastM / (earthRadiusM * Math.cos(toRadians(origin.latitude))));
  return { latitude, longitude };
}

/** Drop a repeated closing corner. The area formula already closes the ring. */
export function normalizeRing(points: LatLng[]): LatLng[] {
  if (points.length < 2) return points;
  const first = points[0];
  const last = points[points.length - 1];
  if (first.latitude === last.latitude && first.longitude === last.longitude) {
    return points.slice(0, -1);
  }
  return points;
}

export function ringCenter(points: LatLng[]): LatLng {
  const latitude = points.reduce((sum, point) => sum + point.latitude, 0) / points.length;
  const longitude = points.reduce((sum, point) => sum + point.longitude, 0) / points.length;
  return { latitude, longitude };
}

/** Local flat-earth area, same formula as the prototype. */
export function polygonAreaSqm(points: LatLng[]): number {
  const usable = points.filter(
    (point) => Number.isFinite(point.latitude) && Number.isFinite(point.longitude),
  );
  if (usable.length < 3) return 0;

  const lat0 = usable.reduce((sum, point) => sum + point.latitude, 0) / usable.length;
  const lng0 = usable.reduce((sum, point) => sum + point.longitude, 0) / usable.length;
  const cosLat = Math.cos(toRadians(lat0));
  const xy = usable.map((point) => ({
    x: toRadians(point.longitude - lng0) * earthRadiusM * cosLat,
    y: toRadians(point.latitude - lat0) * earthRadiusM,
  }));

  let sum = 0;
  for (let index = 0; index < xy.length; index += 1) {
    const next = xy[(index + 1) % xy.length];
    sum += xy[index].x * next.y - next.x * xy[index].y;
  }
  return Math.abs(sum) / 2;
}

export function splitThaiArea(sqm: number): ThaiArea {
  const rounded = Math.max(0, Math.round(sqm));
  const raiDecimal = rounded / sqmPerRai;
  const totalWa = rounded / sqmPerWa;
  const waPerRai = sqmPerRai / sqmPerWa;
  const waPerNgan = sqmPerNgan / sqmPerWa;
  const rai = Math.floor(totalWa / waPerRai);
  const afterRai = totalWa - rai * waPerRai;
  const ngan = Math.floor(afterRai / waPerNgan);
  const wa = afterRai - ngan * 100;
  return { rai, ngan, wa, raiDecimal };
}

export function tonsPerRai(weightTons: number, areaSqm: number): number | null {
  if (!(areaSqm > 0) || !Number.isFinite(weightTons)) return null;
  return weightTons / (areaSqm / sqmPerRai);
}
