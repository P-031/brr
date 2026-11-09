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
  createdAt: Date;
  farmer: { id: string; username: string; displayName: string };
}) {
  return {
    id: plot.id,
    name: plot.name,
    variety: plot.variety,
    ...areaFields(plot.areaSqm),
    center: { latitude: plot.centerLat, longitude: plot.centerLng },
    createdAt: plot.createdAt.toISOString(),
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
  createdAt: Date;
  areaSqm: number;
}) {
  return {
    id: record.id,
    plotId: record.plotId,
    season: record.season,
    weightTons: record.weightTons,
    tonsPerRai: tonsPerRai(record.weightTons, record.areaSqm),
    createdAt: record.createdAt.toISOString(),
  };
}

export function taskJson(task: {
  id: string;
  plotId: string;
  kind: keyof typeof taskName;
  date: Date;
  done: boolean;
}) {
  return {
    id: task.id,
    plotId: task.plotId,
    kind: taskName[task.kind],
    date: formatDate(task.date),
    done: task.done,
  };
}
