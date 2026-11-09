import { Prisma } from "@prisma/client";
import { Router } from "express";
import { z } from "zod";
import { currentUser } from "../auth";
import { normalizeRing, polygonAreaSqm, ringCenter, type LatLng } from "../area";
import { plotsInBox, readBoundary, ringFromGeoJson, writeBoundary } from "../boundary";
import { decodeCursor, encodeCursor } from "../cursor";
import { HttpError, route } from "../http";
import { prisma } from "../prisma";
import { plotDetail, plotSummary, taskJson, taskKindByName, yieldJson } from "../serialize";
import type { AuthUser } from "../types";

const pointSchema = z.object({
  latitude: z.number().finite().gte(-90).lte(90),
  longitude: z.number().finite().gte(-180).lte(180),
});

const pointsSchema = z.array(pointSchema).min(3).max(2000);

const createPlotBody = z.object({
  name: z.string().trim().min(1).max(120),
  variety: z.string().trim().max(120).default(""),
  points: pointsSchema,
});

const updatePlotBody = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    variety: z.string().trim().max(120).optional(),
    points: pointsSchema.optional(),
  })
  .refine((value) => value.name !== undefined || value.variety !== undefined || value.points !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

const yieldBody = z.object({
  season: z.string().trim().min(1).max(80),
  weightTons: z.number().finite().nonnegative(),
});

const updateYieldBody = z
  .object({
    season: z.string().trim().min(1).max(80).optional(),
    weightTons: z.number().finite().nonnegative().optional(),
  })
  .refine((value) => value.season !== undefined || value.weightTons !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

const taskNames = ["ปลูก", "ใส่ปุ๋ย", "พ่นยา", "ตัดอ้อย"] as const;

const taskBody = z.object({
  kind: z.enum(taskNames),
  date: z.string(),
  done: z.boolean().default(false),
});

const updateTaskBody = z
  .object({
    kind: z.enum(taskNames).optional(),
    date: z.string().optional(),
    done: z.boolean().optional(),
  })
  .refine((value) => value.kind !== undefined || value.date !== undefined || value.done !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

const summarySelect = {
  id: true,
  name: true,
  variety: true,
  areaSqm: true,
  centerLat: true,
  centerLng: true,
  createdAt: true,
  farmerId: true,
  farmer: { select: { id: true, username: true, displayName: true } },
} satisfies Prisma.PlotSelect;

function pathId(value: unknown): string {
  const picked = Array.isArray(value) ? value[0] : value;
  return z.string().trim().min(1).max(64).parse(picked);
}

function queryText(value: unknown): string | undefined {
  const picked = Array.isArray(value) ? value[0] : value;
  if (typeof picked !== "string" || picked.trim() === "") return undefined;
  return picked.trim();
}

function parseDate(value: string): Date {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new HttpError(400, "วันที่ต้องเป็น YYYY-MM-DD");
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== value) {
    throw new HttpError(400, "วันที่ไม่ถูกต้อง");
  }
  return date;
}

function measuredRing(points: LatLng[]) {
  const ring = normalizeRing(points);
  if (ring.length < 3) throw new HttpError(400, "ขอบแปลงต้องมีอย่างน้อย 3 จุด");
  const areaSqm = polygonAreaSqm(ring);
  if (!(areaSqm > 0)) throw new HttpError(400, "จุดขอบแปลงคำนวณพื้นที่ไม่ได้");
  return { ring, areaSqm, center: ringCenter(ring) };
}

async function farmerIdsForList(user: AuthUser, requestedFarmerId: string | undefined): Promise<string[]> {
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

async function visiblePlot(user: AuthUser, plotId: string) {
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

async function ownedPlot(user: AuthUser, plotId: string) {
  if (user.role !== "FARMER") throw new HttpError(403, "เฉพาะชาวไร่ที่แก้ข้อมูลได้");
  const plot = await prisma.plot.findUnique({ where: { id: plotId } });
  if (!plot || plot.farmerId !== user.id) throw new HttpError(404, "ไม่พบแปลง");
  return plot;
}

async function toDetail(plot: Awaited<ReturnType<typeof visiblePlot>>) {
  return plotDetail({ ...plot, points: await readBoundary(plot.id) });
}

function coordinate(value: unknown, min: number, max: number) {
  return z.coerce.number().finite().gte(min).lte(max).parse(queryText(value));
}

export const fieldRouter = Router();

fieldRouter.get(
  "/plots",
  route(async (req, res) => {
    const user = currentUser(req);
    const query = z
      .object({
        limit: z.coerce.number().int().min(1).max(50).default(20),
        cursor: z.string().min(1).optional(),
        farmerId: z.string().min(1).optional(),
      })
      .parse({
        limit: queryText(req.query.limit),
        cursor: queryText(req.query.cursor),
        farmerId: queryText(req.query.farmerId),
      });

    const farmerIds = await farmerIdsForList(user, query.farmerId);
    if (farmerIds.length === 0) {
      res.json({ items: [], nextCursor: null });
      return;
    }

    const cursor = query.cursor ? decodeCursor(query.cursor) : undefined;
    const plots = await prisma.plot.findMany({
      where: {
        farmerId: { in: farmerIds },
        ...(cursor
          ? {
              OR: [
                { createdAt: { lt: cursor.createdAt } },
                { AND: [{ createdAt: cursor.createdAt }, { id: { lt: cursor.id } }] },
              ],
            }
          : {}),
      },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: query.limit + 1,
      select: summarySelect,
    });

    const page = plots.slice(0, query.limit);
    const last = page[page.length - 1];
    res.json({
      items: page.map(plotSummary),
      nextCursor: plots.length > query.limit && last ? encodeCursor(last.createdAt, last.id) : null,
    });
  }),
);

fieldRouter.get(
  "/plots/map",
  route(async (req, res) => {
    const user = currentUser(req);
    const box = {
      west: coordinate(req.query.west, -180, 180),
      south: coordinate(req.query.south, -90, 90),
      east: coordinate(req.query.east, -180, 180),
      north: coordinate(req.query.north, -90, 90),
    };
    if (box.west >= box.east || box.south >= box.north) {
      throw new HttpError(400, "กรอบแผนที่ไม่ถูกต้อง");
    }
    const limit = z.coerce.number().int().min(1).max(500).default(200).parse(queryText(req.query.limit));
    const farmerIds = await farmerIdsForList(user, queryText(req.query.farmerId));
    if (farmerIds.length === 0) {
      res.json({ items: [], truncated: false });
      return;
    }

    const rows = await plotsInBox(farmerIds, box, limit + 1);
    res.json({
      items: rows.slice(0, limit).map((row) => ({
        ...plotSummary({
          ...row,
          farmer: { id: row.farmerId, username: row.username, displayName: row.displayName },
        }),
        outline: ringFromGeoJson(row.outline),
      })),
      truncated: rows.length > limit,
    });
  }),
);

fieldRouter.post(
  "/plots",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "FARMER") throw new HttpError(403, "เฉพาะชาวไร่ที่สร้างแปลงได้");

    const body = createPlotBody.parse(req.body);
    const measured = measuredRing(body.points);
    const plotId = await prisma.$transaction(async (tx) => {
      const created = await tx.plot.create({
        data: {
          farmerId: user.id,
          name: body.name,
          variety: body.variety,
          areaSqm: measured.areaSqm,
          centerLat: measured.center.latitude,
          centerLng: measured.center.longitude,
        },
        select: { id: true },
      });
      await writeBoundary(tx, created.id, measured.ring);
      return created.id;
    });

    res.status(201).json(await toDetail(await visiblePlot(user, plotId)));
  }),
);

fieldRouter.get(
  "/plots/:plotId",
  route(async (req, res) => {
    const plot = await visiblePlot(currentUser(req), pathId(req.params.plotId));
    res.json(await toDetail(plot));
  }),
);

fieldRouter.patch(
  "/plots/:plotId",
  route(async (req, res) => {
    const user = currentUser(req);
    const plotId = pathId(req.params.plotId);
    await ownedPlot(user, plotId);
    const body = updatePlotBody.parse(req.body);
    const measured = body.points ? measuredRing(body.points) : undefined;

    await prisma.$transaction(async (tx) => {
      await tx.plot.update({
        where: { id: plotId },
        data: {
          name: body.name,
          variety: body.variety,
          areaSqm: measured?.areaSqm,
          centerLat: measured?.center.latitude,
          centerLng: measured?.center.longitude,
        },
      });
      if (measured) await writeBoundary(tx, plotId, measured.ring);
    });

    res.json(await toDetail(await visiblePlot(user, plotId)));
  }),
);

fieldRouter.delete(
  "/plots/:plotId",
  route(async (req, res) => {
    const user = currentUser(req);
    const plotId = pathId(req.params.plotId);
    await ownedPlot(user, plotId);
    await prisma.plot.delete({ where: { id: plotId } });
    res.status(204).send();
  }),
);

fieldRouter.get(
  "/plots/:plotId/yields",
  route(async (req, res) => {
    const plot = await visiblePlot(currentUser(req), pathId(req.params.plotId));
    const records = await prisma.yieldRecord.findMany({
      where: { plotId: plot.id },
      orderBy: { createdAt: "desc" },
    });
    res.json({
      items: records.map((record) => yieldJson({ ...record, areaSqm: plot.areaSqm })),
    });
  }),
);

fieldRouter.post(
  "/plots/:plotId/yields",
  route(async (req, res) => {
    const user = currentUser(req);
    const plot = await ownedPlot(user, pathId(req.params.plotId));
    const body = yieldBody.parse(req.body);
    const record = await prisma.yieldRecord.create({
      data: { plotId: plot.id, season: body.season, weightTons: body.weightTons },
    });
    res.status(201).json(yieldJson({ ...record, areaSqm: plot.areaSqm }));
  }),
);

fieldRouter.patch(
  "/yields/:yieldId",
  route(async (req, res) => {
    const user = currentUser(req);
    const yieldId = pathId(req.params.yieldId);
    const record = await prisma.yieldRecord.findUnique({ where: { id: yieldId } });
    if (!record) throw new HttpError(404, "ไม่พบผลผลิต");
    const plot = await ownedPlot(user, record.plotId);
    const body = updateYieldBody.parse(req.body);
    const updated = await prisma.yieldRecord.update({
      where: { id: yieldId },
      data: { season: body.season, weightTons: body.weightTons },
    });
    res.json(yieldJson({ ...updated, areaSqm: plot.areaSqm }));
  }),
);

fieldRouter.delete(
  "/yields/:yieldId",
  route(async (req, res) => {
    const user = currentUser(req);
    const yieldId = pathId(req.params.yieldId);
    const record = await prisma.yieldRecord.findUnique({ where: { id: yieldId } });
    if (!record) throw new HttpError(404, "ไม่พบผลผลิต");
    await ownedPlot(user, record.plotId);
    await prisma.yieldRecord.delete({ where: { id: yieldId } });
    res.status(204).send();
  }),
);

fieldRouter.get(
  "/plots/:plotId/tasks",
  route(async (req, res) => {
    const plot = await visiblePlot(currentUser(req), pathId(req.params.plotId));
    const tasks = await prisma.fieldTask.findMany({
      where: { plotId: plot.id },
      orderBy: [{ date: "asc" }, { id: "asc" }],
    });
    res.json({ items: tasks.map(taskJson) });
  }),
);

fieldRouter.post(
  "/plots/:plotId/tasks",
  route(async (req, res) => {
    const user = currentUser(req);
    const plot = await ownedPlot(user, pathId(req.params.plotId));
    const body = taskBody.parse(req.body);
    const task = await prisma.fieldTask.create({
      data: {
        plotId: plot.id,
        kind: taskKindByName[body.kind],
        date: parseDate(body.date),
        done: body.done,
      },
    });
    res.status(201).json(taskJson(task));
  }),
);

fieldRouter.patch(
  "/tasks/:taskId",
  route(async (req, res) => {
    const user = currentUser(req);
    const taskId = pathId(req.params.taskId);
    const existing = await prisma.fieldTask.findUnique({ where: { id: taskId } });
    if (!existing) throw new HttpError(404, "ไม่พบงาน");
    await ownedPlot(user, existing.plotId);
    const body = updateTaskBody.parse(req.body);
    const task = await prisma.fieldTask.update({
      where: { id: taskId },
      data: {
        kind: body.kind ? taskKindByName[body.kind] : undefined,
        date: body.date ? parseDate(body.date) : undefined,
        done: body.done,
      },
    });
    res.json(taskJson(task));
  }),
);

fieldRouter.delete(
  "/tasks/:taskId",
  route(async (req, res) => {
    const user = currentUser(req);
    const taskId = pathId(req.params.taskId);
    const existing = await prisma.fieldTask.findUnique({ where: { id: taskId } });
    if (!existing) throw new HttpError(404, "ไม่พบงาน");
    await ownedPlot(user, existing.plotId);
    await prisma.fieldTask.delete({ where: { id: taskId } });
    res.status(204).send();
  }),
);
