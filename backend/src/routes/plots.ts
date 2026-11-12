import type { Prisma } from "@prisma/client";
import { Router } from "express";
import { z } from "zod";
import { currentUser } from "../auth";
import { isValidRing, lockBoundaries, overlappingPlots, plotsInBox, ringFromGeoJson, writeBoundary } from "../boundary";
import { decodeCursor, encodeCursor } from "../cursor";
import { HttpError, route } from "../http";
import { baseVersion, clientId, refuseDeleted, versionConflict, versionQuery, wasDeletedBy } from "../offline";
import { blockingOverlaps, overlapError } from "../overlap";
import { farmerIdsForList, ownedPlot, requireFarmer, summarySelect, toDetail, visiblePlot } from "../plotAccess";
import { prisma } from "../prisma";
import { areaFields, plotSummary, surveyJson, taskJson, taskKindByName, yieldJson } from "../serialize";
import { measureSurvey, surveyRules, type MeasuredSurvey, type Survey } from "../survey";

const isoTime = z
  .string()
  .datetime({ offset: true })
  .transform((value) => new Date(value));

const cornerSchema = z.object({
  latitude: z.number().finite().gte(-90).lte(90),
  longitude: z.number().finite().gte(-180).lte(180),
  accuracyM: z.number().finite().positive().max(10_000),
  capturedAt: isoTime,
});

/** One more corner than the rule allows, in case the walk ends back on the first corner. */
const surveySchema = z.object({
  startedAt: isoTime,
  finishedAt: isoTime,
  corners: z.array(cornerSchema).min(surveyRules.minCorners).max(surveyRules.maxCorners + 1),
});

const createPlotBody = z.object({
  id: clientId,
  name: z.string().trim().min(1).max(120),
  variety: z.string().trim().max(120).default(""),
  survey: surveySchema,
});

const updatePlotBody = z
  .object({
    version: baseVersion,
    name: z.string().trim().min(1).max(120).optional(),
    variety: z.string().trim().max(120).optional(),
    survey: surveySchema.optional(),
  })
  .refine((value) => value.name !== undefined || value.variety !== undefined || value.survey !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

const overlapCheckBody = z.object({
  survey: surveySchema,
  plotId: z.string().trim().min(1).max(64).optional(),
});

const yieldBody = z.object({
  id: clientId,
  season: z.string().trim().min(1).max(80),
  weightTons: z.number().finite().nonnegative(),
});

const updateYieldBody = z
  .object({
    version: baseVersion,
    season: z.string().trim().min(1).max(80).optional(),
    weightTons: z.number().finite().nonnegative().optional(),
  })
  .refine((value) => value.season !== undefined || value.weightTons !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

const taskNames = ["ปลูก", "ใส่ปุ๋ย", "พ่นยา", "ตัดอ้อย"] as const;

const taskBody = z.object({
  id: clientId,
  kind: z.enum(taskNames),
  date: z.string(),
  done: z.boolean().default(false),
});

const updateTaskBody = z
  .object({
    version: baseVersion,
    kind: z.enum(taskNames).optional(),
    date: z.string().optional(),
    done: z.boolean().optional(),
  })
  .refine((value) => value.kind !== undefined || value.date !== undefined || value.done !== undefined, {
    message: "ไม่มีข้อมูลให้แก้",
  });

/** Boundary saves wait on one lock, so give them longer than Prisma's 5 second default. */
const boundaryTx = { maxWait: 10_000, timeout: 20_000 };

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

function coordinate(value: unknown, min: number, max: number) {
  return z.coerce.number().finite().gte(min).lte(max).parse(queryText(value));
}

/** Call with the boundary lock held. */
async function assertFits(tx: Prisma.TransactionClient, measured: MeasuredSurvey, farmerId: string, plotId?: string) {
  if (!(await isValidRing(tx, measured.ring))) {
    throw new HttpError(400, "ขอบแปลงไม่ถูกต้อง", { code: "SURVEY_INVALID" });
  }
  const rows = await overlappingPlots(tx, measured.ring, plotId);
  const conflicts = blockingOverlaps(rows, measured.areaSqm, farmerId);
  if (conflicts.length > 0) throw overlapError(conflicts);
}

function surveyRecord(plotId: string, survey: Survey, measured: MeasuredSurvey) {
  return {
    plotId,
    startedAt: survey.startedAt,
    finishedAt: survey.finishedAt,
    areaSqm: measured.areaSqm,
    corners: measured.corners.map((corner) => ({
      latitude: corner.latitude,
      longitude: corner.longitude,
      accuracyM: corner.accuracyM,
      capturedAt: corner.capturedAt.toISOString(),
    })),
  };
}

export const fieldRouter = Router();

fieldRouter.get("/survey-rules", (_req, res) => {
  res.json(surveyRules);
});

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

/** Same checks as saving, without saving. Lets the app warn while the farmer is still in the field. */
fieldRouter.post(
  "/plots/overlap-check",
  route(async (req, res) => {
    const user = currentUser(req);
    requireFarmer(user);
    const body = overlapCheckBody.parse(req.body);
    if (body.plotId) await ownedPlot(user, body.plotId);

    const measured = measureSurvey(body.survey, new Date());
    const rows = await overlappingPlots(prisma, measured.ring, body.plotId);
    res.json({
      ...areaFields(measured.areaSqm),
      points: measured.ring,
      conflicts: blockingOverlaps(rows, measured.areaSqm, user.id),
    });
  }),
);

fieldRouter.post(
  "/plots",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "FARMER") throw new HttpError(403, "เฉพาะชาวไร่ที่สร้างแปลงได้");
    const body = createPlotBody.parse(req.body);

    const existing = await prisma.plot.findUnique({ where: { id: body.id }, select: { farmerId: true } });
    if (existing) {
      if (existing.farmerId !== user.id) throw new HttpError(409, "รหัสแปลงนี้ถูกใช้แล้ว");
      res.json(await toDetail(await visiblePlot(user, body.id)));
      return;
    }
    await refuseDeleted("PLOT", body.id);

    const measured = measureSurvey(body.survey, new Date());
    await prisma.$transaction(async (tx) => {
      await lockBoundaries(tx);
      await assertFits(tx, measured, user.id);
      await tx.plot.create({
        data: {
          id: body.id,
          farmerId: user.id,
          name: body.name,
          variety: body.variety,
          areaSqm: measured.areaSqm,
          centerLat: measured.center.latitude,
          centerLng: measured.center.longitude,
          surveyedAt: body.survey.finishedAt,
        },
      });
      await writeBoundary(tx, body.id, measured.ring);
      await tx.plotSurvey.create({ data: surveyRecord(body.id, body.survey, measured) });
    }, boundaryTx);

    res.status(201).json(await toDetail(await visiblePlot(user, body.id)));
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
    const survey = body.survey;
    const measured = survey ? measureSurvey(survey, new Date()) : undefined;

    const saved = await prisma.$transaction(async (tx) => {
      if (measured) await lockBoundaries(tx);
      const updated = await tx.plot.updateMany({
        where: { id: plotId, version: body.version },
        data: {
          name: body.name,
          variety: body.variety,
          areaSqm: measured?.areaSqm,
          centerLat: measured?.center.latitude,
          centerLng: measured?.center.longitude,
          surveyedAt: survey?.finishedAt,
          version: { increment: 1 },
        },
      });
      if (updated.count === 0) return false;
      if (survey && measured) {
        await assertFits(tx, measured, user.id, plotId);
        await writeBoundary(tx, plotId, measured.ring);
        await tx.plotSurvey.create({ data: surveyRecord(plotId, survey, measured) });
      }
      return true;
    }, boundaryTx);

    const detail = await toDetail(await visiblePlot(user, plotId));
    if (!saved) throw versionConflict(detail);
    res.json(detail);
  }),
);

fieldRouter.delete(
  "/plots/:plotId",
  route(async (req, res) => {
    const user = currentUser(req);
    requireFarmer(user);
    const plotId = pathId(req.params.plotId);
    const version = versionQuery(req.query.version);

    const plot = await prisma.plot.findUnique({ where: { id: plotId }, select: { farmerId: true } });
    if (!plot || plot.farmerId !== user.id) {
      if (await wasDeletedBy("PLOT", plotId, user.id)) {
        res.status(204).send();
        return;
      }
      throw new HttpError(404, "ไม่พบแปลง");
    }

    const removed = await prisma.$transaction(async (tx) => {
      const result = await tx.plot.deleteMany({ where: { id: plotId, ...(version ? { version } : {}) } });
      if (result.count === 0) return false;
      await tx.deletedRecord.create({ data: { kind: "PLOT", recordId: plotId, farmerId: user.id } });
      return true;
    });
    if (!removed) throw versionConflict(await toDetail(await visiblePlot(user, plotId)));
    res.status(204).send();
  }),
);

fieldRouter.get(
  "/plots/:plotId/surveys",
  route(async (req, res) => {
    const plot = await visiblePlot(currentUser(req), pathId(req.params.plotId));
    const surveys = await prisma.plotSurvey.findMany({
      where: { plotId: plot.id },
      orderBy: { createdAt: "desc" },
    });
    res.json({ items: surveys.map(surveyJson) });
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

    const existing = await prisma.yieldRecord.findUnique({ where: { id: body.id } });
    if (existing) {
      if (existing.plotId !== plot.id) throw new HttpError(409, "รหัสผลผลิตนี้ถูกใช้แล้ว");
      res.json(yieldJson({ ...existing, areaSqm: plot.areaSqm }));
      return;
    }
    await refuseDeleted("YIELD", body.id);

    const record = await prisma.yieldRecord.create({
      data: { id: body.id, plotId: plot.id, season: body.season, weightTons: body.weightTons },
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
    if (!record) {
      await refuseDeleted("YIELD", yieldId);
      throw new HttpError(404, "ไม่พบผลผลิต");
    }
    const plot = await ownedPlot(user, record.plotId);
    const body = updateYieldBody.parse(req.body);

    const updated = await prisma.yieldRecord.updateMany({
      where: { id: yieldId, version: body.version },
      data: { season: body.season, weightTons: body.weightTons, version: { increment: 1 } },
    });
    const current = await prisma.yieldRecord.findUniqueOrThrow({ where: { id: yieldId } });
    const json = yieldJson({ ...current, areaSqm: plot.areaSqm });
    if (updated.count === 0) throw versionConflict(json);
    res.json(json);
  }),
);

fieldRouter.delete(
  "/yields/:yieldId",
  route(async (req, res) => {
    const user = currentUser(req);
    requireFarmer(user);
    const yieldId = pathId(req.params.yieldId);
    const version = versionQuery(req.query.version);

    const record = await prisma.yieldRecord.findUnique({ where: { id: yieldId } });
    if (!record) {
      if (await wasDeletedBy("YIELD", yieldId, user.id)) {
        res.status(204).send();
        return;
      }
      throw new HttpError(404, "ไม่พบผลผลิต");
    }
    const plot = await ownedPlot(user, record.plotId);

    const removed = await prisma.$transaction(async (tx) => {
      const result = await tx.yieldRecord.deleteMany({ where: { id: yieldId, ...(version ? { version } : {}) } });
      if (result.count === 0) return false;
      await tx.deletedRecord.create({
        data: { kind: "YIELD", recordId: yieldId, farmerId: user.id, plotId: plot.id },
      });
      return true;
    });
    if (!removed) {
      const current = await prisma.yieldRecord.findUniqueOrThrow({ where: { id: yieldId } });
      throw versionConflict(yieldJson({ ...current, areaSqm: plot.areaSqm }));
    }
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

    const existing = await prisma.fieldTask.findUnique({ where: { id: body.id } });
    if (existing) {
      if (existing.plotId !== plot.id) throw new HttpError(409, "รหัสงานนี้ถูกใช้แล้ว");
      res.json(taskJson(existing));
      return;
    }
    await refuseDeleted("TASK", body.id);

    const task = await prisma.fieldTask.create({
      data: {
        id: body.id,
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
    if (!existing) {
      await refuseDeleted("TASK", taskId);
      throw new HttpError(404, "ไม่พบงาน");
    }
    await ownedPlot(user, existing.plotId);
    const body = updateTaskBody.parse(req.body);

    const updated = await prisma.fieldTask.updateMany({
      where: { id: taskId, version: body.version },
      data: {
        kind: body.kind ? taskKindByName[body.kind] : undefined,
        date: body.date ? parseDate(body.date) : undefined,
        done: body.done,
        version: { increment: 1 },
      },
    });
    const current = taskJson(await prisma.fieldTask.findUniqueOrThrow({ where: { id: taskId } }));
    if (updated.count === 0) throw versionConflict(current);
    res.json(current);
  }),
);

fieldRouter.delete(
  "/tasks/:taskId",
  route(async (req, res) => {
    const user = currentUser(req);
    requireFarmer(user);
    const taskId = pathId(req.params.taskId);
    const version = versionQuery(req.query.version);

    const existing = await prisma.fieldTask.findUnique({ where: { id: taskId } });
    if (!existing) {
      if (await wasDeletedBy("TASK", taskId, user.id)) {
        res.status(204).send();
        return;
      }
      throw new HttpError(404, "ไม่พบงาน");
    }
    const plot = await ownedPlot(user, existing.plotId);

    const removed = await prisma.$transaction(async (tx) => {
      const result = await tx.fieldTask.deleteMany({ where: { id: taskId, ...(version ? { version } : {}) } });
      if (result.count === 0) return false;
      await tx.deletedRecord.create({
        data: { kind: "TASK", recordId: taskId, farmerId: user.id, plotId: plot.id },
      });
      return true;
    });
    if (!removed) throw versionConflict(taskJson(await prisma.fieldTask.findUniqueOrThrow({ where: { id: taskId } })));
    res.status(204).send();
  }),
);
