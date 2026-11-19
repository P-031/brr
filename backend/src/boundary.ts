import { Prisma } from "@prisma/client";
import type { LatLng } from "./area";
import { prisma } from "./prisma";

type Db = Pick<typeof prisma, "$executeRaw" | "$queryRaw">;

export type Box = {
  west: number;
  south: number;
  east: number;
  north: number;
};

export type MapPlotRow = {
  id: string;
  name: string;
  productionYear: string | null;
  outline: string | null;
};

/** GeoJSON is [longitude, latitude] and a ring must end on its first corner. */
function polygonGeoJson(ring: LatLng[]): string {
  const coordinates = ring.map((point) => [point.longitude, point.latitude]);
  coordinates.push(coordinates[0]);
  return JSON.stringify({ type: "Polygon", coordinates: [coordinates] });
}

export function ringFromGeoJson(text: string | null): LatLng[] {
  if (!text) return [];
  const geometry = JSON.parse(text) as { coordinates?: number[][][] };
  const outer = geometry.coordinates?.[0] ?? [];
  const points = outer.map(([longitude, latitude]) => ({ latitude, longitude }));
  return points.slice(0, -1);
}

export async function writeBoundary(db: Db, plotId: string, ring: LatLng[]): Promise<void> {
  await db.$executeRaw`
    UPDATE "Plot"
    SET boundary = ST_SetSRID(ST_GeomFromGeoJSON(${polygonGeoJson(ring)}), 4326)
    WHERE id = ${plotId}
  `;
}

export async function readBoundary(plotId: string): Promise<LatLng[]> {
  const rows = await prisma.$queryRaw<Array<{ geojson: string | null }>>`
    SELECT ST_AsGeoJSON(boundary) AS geojson FROM "Plot" WHERE id = ${plotId}
  `;
  return ringFromGeoJson(rows[0]?.geojson ?? null);
}

/** Plots whose outline touches the box — outlines return exactly
 *  as saved (no simplification; pins must match what was recorded).
 *  [years] filters productionYear; include `null` inside to also keep
 *  plots without a production year. undefined = no year filter. */
export async function plotsInBox(
  farmerIds: string[],
  box: Box,
  limit: number,
  years?: (string | null)[],
): Promise<MapPlotRow[]> {
  const named = years?.filter((y): y is string => y != null) ?? [];
  const yearFilter =
    years === undefined
      ? Prisma.empty
      : years.length === 0
        ? Prisma.sql`AND false` // เลือกไม่เลือกปีเลย = ไม่มีแปลง
        : years.includes(null) && named.length === 0
        ? Prisma.sql`AND p."productionYear" IS NULL`
        : years.includes(null)
          ? Prisma.sql`AND (p."productionYear" IN (${Prisma.join(named)}) OR p."productionYear" IS NULL)`
          : Prisma.sql`AND p."productionYear" IN (${Prisma.join(named)})`;
  // เลือกเฉพาะฟิลด์ที่แอปต้องใช้ render แผนที่ — meta/owner/
  // variety หนักๆ ไม่ต้องส่ง bulk (แตะแปลงค่อย GET /plots/:id)
  return prisma.$queryRaw<MapPlotRow[]>`
    SELECT p.id, p.name, p."productionYear",
           -- 6 ตำแหน่งทศนิยม ≈ ±0.1ม. (เกินความแม่น GPS แล้ว)
           -- ลด payload ~25% โดยจุดยังครบเหมือนเดิม
           ST_AsGeoJSON(p.boundary, 6) AS outline
    FROM "Plot" p
    WHERE p."farmerId" IN (${Prisma.join(farmerIds)})
      AND p.boundary && ST_MakeEnvelope(
        ${box.west}::float8, ${box.south}::float8, ${box.east}::float8, ${box.north}::float8, 4326
      )
      ${yearFilter}
    ORDER BY p."areaSqm" DESC, p.id
    LIMIT ${limit}
  `;
}
