import type { Prisma } from "@prisma/client";
import { readBoundary } from "./boundary";
import { HttpError } from "./http";
import { prisma } from "./prisma";
import { plotDetail } from "./serialize";
import type { AuthUser } from "./types";

export const summarySelect = {
  id: true,
  name: true,
  variety: true,
  areaSqm: true,
  centerLat: true,
  centerLng: true,
  version: true,
  surveyedAt: true,
  createdAt: true,
  updatedAt: true,
  farmerId: true,
  farmer: { select: { id: true, username: true, displayName: true } },
} satisfies Prisma.PlotSelect;

export type PlotSummaryRow = Prisma.PlotGetPayload<{ select: typeof summarySelect }>;

export async function farmerIdsForList(user: AuthUser, requestedFarmerId: string | undefined): Promise<string[]> {
  if (user.role === "FARMER") return [user.id];

  const links = await prisma.farmerCare.findMany({
    where: { officerId: user.id },
    select: { farmerId: true },
  });
  const assigned = new Set(links.map((link) => link.farmerId));
  if (!requestedFarmerId) return [...assigned];
  if (!assigned.has(requestedFarmerId)) throw new HttpError(404, "ไม่พบชาวไร่");
  return [requestedFarmerId];
}

export async function visiblePlot(user: AuthUser, plotId: string): Promise<PlotSummaryRow> {
  const plot = await prisma.plot.findUnique({
    where: { id: plotId },
    select: summarySelect,
  });
  if (!plot) throw new HttpError(404, "ไม่พบแปลง");

  if (user.role === "FARMER") {
    if (plot.farmerId !== user.id) throw new HttpError(404, "ไม่พบแปลง");
    return plot;
  }

  const link = await prisma.farmerCare.findUnique({
    where: { officerId_farmerId: { officerId: user.id, farmerId: plot.farmerId } },
  });
  if (!link) throw new HttpError(404, "ไม่พบแปลง");
  return plot;
}

export function requireFarmer(user: AuthUser): void {
  if (user.role !== "FARMER") throw new HttpError(403, "เฉพาะชาวไร่ที่แก้ข้อมูลได้");
}

export async function ownedPlot(user: AuthUser, plotId: string) {
  requireFarmer(user);
  const plot = await prisma.plot.findUnique({ where: { id: plotId } });
  if (!plot || plot.farmerId !== user.id) throw new HttpError(404, "ไม่พบแปลง");
  return plot;
}

export async function toDetail(plot: PlotSummaryRow) {
  return plotDetail({ ...plot, points: await readBoundary(plot.id) });
}
