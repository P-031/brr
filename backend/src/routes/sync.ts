import { Router } from "express";
import { z } from "zod";
import { currentUser } from "../auth";
import { readBoundaries } from "../boundary";
import { route } from "../http";
import { syncOverlapMs } from "../offline";
import { farmerIdsForList, summarySelect } from "../plotAccess";
import { prisma } from "../prisma";
import { plotDetail, taskJson, yieldJson } from "../serialize";

export const syncRouter = Router();

function queryText(value: unknown): string | undefined {
  const picked = Array.isArray(value) ? value[0] : value;
  if (typeof picked !== "string" || picked.trim() === "") return undefined;
  return picked.trim();
}

/**
 * Everything the caller may read that changed after `since`. Leave `since` out for a full copy.
 * Records can come back more than once; apply them by id and keep the higher version.
 * A deleted plot takes its yields and tasks with it.
 */
syncRouter.get(
  "/sync",
  route(async (req, res) => {
    const started = Date.now();
    const user = currentUser(req);
    const query = z
      .object({
        since: z.string().datetime({ offset: true }).optional(),
        farmerId: z.string().min(1).max(64).optional(),
      })
      .parse({ since: queryText(req.query.since), farmerId: queryText(req.query.farmerId) });

    const since = query.since ? new Date(query.since) : undefined;
    const farmerIds = await farmerIdsForList(user, query.farmerId);
    const changed = since ? { gt: since } : undefined;

    const [plots, yields, tasks, deleted] = await Promise.all([
      prisma.plot.findMany({
        where: { farmerId: { in: farmerIds }, updatedAt: changed },
        orderBy: [{ updatedAt: "asc" }, { id: "asc" }],
        select: summarySelect,
      }),
      prisma.yieldRecord.findMany({
        where: { plot: { farmerId: { in: farmerIds } }, updatedAt: changed },
        orderBy: [{ updatedAt: "asc" }, { id: "asc" }],
        include: { plot: { select: { areaSqm: true } } },
      }),
      prisma.fieldTask.findMany({
        where: { plot: { farmerId: { in: farmerIds } }, updatedAt: changed },
        orderBy: [{ updatedAt: "asc" }, { id: "asc" }],
      }),
      since
        ? prisma.deletedRecord.findMany({
            where: { farmerId: { in: farmerIds }, deletedAt: { gt: since } },
            orderBy: { deletedAt: "asc" },
          })
        : Promise.resolve([]),
    ]);
    const outlines = await readBoundaries(plots.map((plot) => plot.id));

    res.json({
      next: new Date(started - syncOverlapMs).toISOString(),
      plots: plots.map((plot) => plotDetail({ ...plot, points: outlines.get(plot.id) ?? [] })),
      yields: yields.map(({ plot, ...record }) => yieldJson({ ...record, areaSqm: plot.areaSqm })),
      tasks: tasks.map(taskJson),
      deleted: deleted.map((record) => ({
        kind: record.kind.toLowerCase(),
        id: record.recordId,
        plotId: record.plotId,
        deletedAt: record.deletedAt.toISOString(),
      })),
    });
  }),
);
