import type { OverlapRow } from "./boundary";
import { HttpError } from "./http";
import { allowedOverlapSqm } from "./survey";

export type OverlapConflict = {
  own: boolean;
  /** Only shown for the caller's own plots. Other farmers' plots stay private. */
  plotId?: string;
  name?: string;
  overlapSqm: number;
  /** Share of the smaller of the two plots. */
  overlapPercent: number;
};

export function blockingOverlaps(rows: OverlapRow[], areaSqm: number, farmerId: string): OverlapConflict[] {
  return rows
    .filter((row) => row.overlapSqm > allowedOverlapSqm(areaSqm, row.areaSqm))
    .map((row) => {
      const own = row.farmerId === farmerId;
      const overlapPercent = (row.overlapSqm / Math.min(areaSqm, row.areaSqm)) * 100;
      return {
        own,
        ...(own ? { plotId: row.id, name: row.name } : {}),
        overlapSqm: Math.round(row.overlapSqm),
        overlapPercent: Math.round(overlapPercent * 10) / 10,
      };
    });
}

export function overlapError(conflicts: OverlapConflict[]): HttpError {
  return new HttpError(409, "แปลงนี้ทับกับแปลงที่วัดไว้แล้ว", { code: "PLOT_OVERLAP", conflicts });
}
