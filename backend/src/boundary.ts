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
  variety: string;
  areaSqm: number;
  centerLat: number;
  centerLng: number;
  createdAt: Date;
  farmerId: string;
  username: string;
  displayName: string;
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

/** Plots whose outline touches the box, with corners thinned to the map's scale. */
export async function plotsInBox(farmerIds: string[], box: Box, limit: number): Promise<MapPlotRow[]> {
  const tolerance = Math.max(box.east - box.west, box.north - box.south) / 2000;
  return prisma.$queryRaw<MapPlotRow[]>`
    SELECT p.id, p.name, p.variety, p."areaSqm", p."centerLat", p."centerLng", p."createdAt",
           p."farmerId", u.username, u."displayName",
           ST_AsGeoJSON(ST_SimplifyPreserveTopology(p.boundary, ${tolerance}::float8)) AS outline
    FROM "Plot" p
    JOIN "User" u ON u.id = p."farmerId"
    WHERE p."farmerId" IN (${Prisma.join(farmerIds)})
      AND p.boundary && ST_MakeEnvelope(
        ${box.west}::float8, ${box.south}::float8, ${box.east}::float8, ${box.north}::float8, 4326
      )
    ORDER BY p."areaSqm" DESC, p.id
    LIMIT ${limit}
  `;
}
