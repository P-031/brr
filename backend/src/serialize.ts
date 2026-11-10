import type { AppRole } from "./access";
import { splitThaiArea, tonsPerRai, type LatLng } from "./area";

const roleName: Record<AppRole, "farmer" | "officer"> = {
  FARMER: "farmer",
  OFFICER: "officer",
};

const taskName = {
  PLANT: "ปลูก",
  FERTILIZE: "ใส่ปุ๋ย",
  SPRAY: "พ่นยา",
  HARVEST: "ตัดอ้อย",
} as const;

export type TaskName = (typeof taskName)[keyof typeof taskName];

export const taskKindByName = {
  ปลูก: "PLANT",
  ใส่ปุ๋ย: "FERTILIZE",
  พ่นยา: "SPRAY",
  ตัดอ้อย: "HARVEST",
} as const;

export function formatDate(date: Date): string {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

export function publicProfile(user: { id: string; username: string; role: AppRole; displayName: string }) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName,
    role: roleName[user.role],
  };
}

export function areaFields(areaSqm: number) {
  return { areaSqm, area: splitThaiArea(areaSqm) };
}

export function plotSummary(plot: {
  id: string;
  name: string;
  variety: string;
  areaSqm: number;
  centerLat: number;
  centerLng: number;
  version: number;
  surveyedAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
  farmer: { id: string; username: string; displayName: string };
}) {
  return {
    id: plot.id,
    name: plot.name,
    variety: plot.variety,
    ...areaFields(plot.areaSqm),
    center: { latitude: plot.centerLat, longitude: plot.centerLng },
    version: plot.version,
    surveyedAt: plot.surveyedAt?.toISOString() ?? null,
    createdAt: plot.createdAt.toISOString(),
    updatedAt: plot.updatedAt.toISOString(),
    farmer: {
      id: plot.farmer.id,
      username: plot.farmer.username,
      displayName: plot.farmer.displayName,
    },
  };
}

export function plotDetail(
  plot: Parameters<typeof plotSummary>[0] & {
    points: LatLng[];
  },
) {
  return { ...plotSummary(plot), points: plot.points };
}

export function yieldJson(record: {
  id: string;
  plotId: string;
  season: string;
  weightTons: number;
  version: number;
  createdAt: Date;
  updatedAt: Date;
  areaSqm: number;
}) {
  return {
    id: record.id,
    plotId: record.plotId,
    season: record.season,
    weightTons: record.weightTons,
    tonsPerRai: tonsPerRai(record.weightTons, record.areaSqm),
    version: record.version,
    createdAt: record.createdAt.toISOString(),
    updatedAt: record.updatedAt.toISOString(),
  };
}

export function taskJson(task: {
  id: string;
  plotId: string;
  kind: keyof typeof taskName;
  date: Date;
  done: boolean;
  version: number;
  updatedAt: Date;
}) {
  return {
    id: task.id,
    plotId: task.plotId,
    kind: taskName[task.kind],
    date: formatDate(task.date),
    done: task.done,
    version: task.version,
    updatedAt: task.updatedAt.toISOString(),
  };
}

export function surveyJson(survey: {
  id: string;
  plotId: string;
  startedAt: Date;
  finishedAt: Date;
  corners: unknown;
  areaSqm: number;
  createdAt: Date;
}) {
  return {
    id: survey.id,
    plotId: survey.plotId,
    startedAt: survey.startedAt.toISOString(),
    finishedAt: survey.finishedAt.toISOString(),
    corners: survey.corners,
    ...areaFields(survey.areaSqm),
    createdAt: survey.createdAt.toISOString(),
  };
}
