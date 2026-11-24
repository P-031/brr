import { Prisma } from "@prisma/client";
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
import { activityJson, areaFields, plotSummary, surveyJson, taskJson, taskKindByName, yieldJson } from "../serialize";
import { normalizeRing, polygonAreaSqm, ringCenter, type LatLng } from "../area";
import { readBoundaries } from "../boundary";
import { firstCrossingEdge, measureSurvey, surveyRules, type MeasuredSurvey, type Survey } from "../survey";
import { plotMeta } from "../serialize"
import { cutStatuses  } from "../serialize";
import { randomUUID } from "node:crypto"

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

const seasonText = z.string().trim().min(1).max(80);

const optionalText = (max: number) => z.string().trim().max(max).optional();

const pointSchema = z.object({
  latitude: z.number().finite().gte(-90).lte(90),
  longitude: z.number().finite().gte(-180).lte(180),
});

const formFields = {
  officerName: optionalText(120),
  project: optionalText(120),
  caneGroup: optionalText(120),
  zone: optionalText(120),
  province: optionalText(120),
  district: optionalText(120),
  subdistrict: optionalText(120),
  village: optionalText(120),
  rootNo: optionalText(40),
  sequenceNo: optionalText(40),
  prevPlotNo: optionalText(120),
  caneType: optionalText(120),
  caneVariety: optionalText(120),
  ownership: optionalText(120),
  terrain: optionalText(120),
  hasLoss: optionalText(200),
  lossRai: z.number().finite().nonnegative().optional(),
  targetYield: z.number().finite().nonnegative().max(30).optional(),
  note: optionalText(2000),
  groupKind: z.enum(["harvest", "maintain"]).optional(),
};

const createPlotBody = z
.object({
  id: clientId,
  name: z.string().trim().min(1).max(120),
  variety: z.string().trim().max(120).default(""),
  season: seasonText.optional(),
  productionYear: seasonText.optional(),
  farmerId: z.string().trim().min(1).max(64).optional(),
  ...formFields,
  survey: surveySchema.optional(),
  points: z.array(pointSchema).min(surveyRules.minCorners).max(surveyRules.maxCorners).optional(),
})
.refine((value) => value.survey !== undefined || value.points !== undefined, {
  message: "ต้องมีจุดมุมของแปลง",
});

const updatePlotBody = z
.object({
  version: baseVersion,
  name: z.string().trim().min(1).max(120).optional(),
  variety: z.string().trim().max(120).optional(),
  season: seasonText.optional(),
  productionYear: seasonText.optional(),
  ...formFields,
  survey: surveySchema.optional(),
  cutStatus: z.enum(cutStatuses).optional(),
})
.refine((value) => Object.entries(value).some(([key, item]) => key !== "version" && item !== undefined), {
  message: "ไม่มีข้อมูลให้แก้",
});

const overlapCheckBody = z.object({
  survey: surveySchema,
  season: seasonText,
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

const taskNames = ["ปลูก", "ใส่ปุ๋ย", "พ่นยา", "ตัดอ้อย", "เตรียมแปลง", "ดูแล"] as const;

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
async function assertFits(
  tx: Prisma.TransactionClient,
  measured: MeasuredSurvey,
  farmerId: string,
  season: string,
  plotId?: string,
) {
  if (!(await isValidRing(tx, measured.ring))) {
    throw new HttpError(400, "ขอบแปลงไม่ถูกต้อง", { code: "SURVEY_INVALID"});
  }
  const rows = await overlappingPlots(tx, measured.ring, season, plotId);
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
  "/seasons",
  route(async (req, res) => {
    const farmerIds = await farmerIdsForList(currentUser(req), queryText(req.query.farmerId));
    if (farmerIds.length === 0) {
      res.json({ items: [] });
      return;
    }
    const rows = await prisma.plot.findMany({
      where: { farmerId: { in: farmerIds } },
      distinct: ["season"],
      select: { season: true },
      orderBy: { season: "desc" },
    });
    res.json({ items: rows.map((row) => row.season) });
  }),
);

function csv(value: unknown): string[] {
  const text = queryText(value);
  if (!text) return [];
  return text.split(",").map((item) => item.trim()).filter((item) => item !== "");
}

function measurePoints(points: LatLng[]): MeasuredSurvey {
  const ring = normalizeRing(points);
  if (ring.length < surveyRules.minCorners) {
    throw new HttpError(400, `ต้องมีจุดมุมอย่างน้อย ${surveyRules.minCorners} จุด`, { code: "SURVEY_INVALID"});
  }
  const crossing = firstCrossingEdge(ring);
  if (crossing >= 0) {
    throw new HttpError(400, `ขอบแปลงตัดกันเองที่ช่วงมุม ${crossing}`, {
       code: "SURVEY_CROSSING",
       corner: crossing + 1,      
      });
  }
  const areaSqm = polygonAreaSqm(ring);
  if (areaSqm < surveyRules.minAreaSqm) {
    throw new HttpError(400, `แปลงต้องใหญ่อย่างน้อย ${surveyRules.minAreaSqm} ตารางเมตร`, { code: "SURVEY_INVALID"});
  }
  const capturedAt = new Date();
  return {
    ring,
    areaSqm,
    center: ringCenter(ring),
    corners: ring.map((point) => ({...point, accuracyM: 0, capturedAt})),
  };
  };

fieldRouter.get(
  "/plots/years",
  route(async (req, res) => {
    const farmerIds =await farmerIdsForList(currentUser(req), queryText(req.query.farmerId));
    if (farmerIds.length === 0) {
      res.json({ items: [] });
      return;
    }
    const rows =await prisma.plot.groupBy({
      by: ["season"],
      where: { farmerId: { in: farmerIds } },
      _count: {_all: true},
      orderBy: { season: "desc"},
    });
    res.json({
      items: rows.map((row) => ({
        year: row.season === "" ? null : row.season,
        count: row._count._all,
      })),
    });
  }),
);

fieldRouter.get(
  "/plots",
  route(async (req, res) => {
    const user = currentUser(req);
    const limit = z.coerce.number().int().min(1).max(50).default(30).parse(queryText(req.query.limit));
    const cursorText = queryText(req.query.cursor);
    const season = queryText(req.query.season);
    const years = csv(req.query.years);
    const includeBlank = queryText(req.query.nullYear) === "1";
    const zones = csv(req.query.zone);
    const caneTypes = csv(req.query.caneType);
    const planted = queryText(req.query.planted);
    const groupKind = queryText(req.query.groupKind);
    const search = queryText(req.query.search);
    const farmerIds = await farmerIdsForList(user, queryText(req.query.farmerId));
    if (farmerIds.length === 0 ) {
      res.json ({ items: [], nextCursor: null , total: 0});
      return;
    }

    const and: Prisma.PlotWhereInput[] = [{ farmerId: { in: farmerIds } }];
    if (season) and.push({ season });
    else if (years.length > 0 || includeBlank) {
      const yearOr: Prisma.PlotWhereInput[] = [];
      if (years.length > 0 ) yearOr.push({ season: { in: years } } );
      if (includeBlank) yearOr.push({ season: "" });
      and.push({ OR: yearOr });
    }
    if (zones.length > 0) and.push({ zone: { in: zones } });
    if (caneTypes.length > 0) and.push({ caneType: { in: caneTypes } });
    if (planted === "1") and.push({ caneType: { not: ""} });
    if (planted === "0") and.push({ OR: [{ caneType: null },  { caneType: "" }] });
    if (groupKind === "harvest" || groupKind === "maintain") {
      const word = groupKind === "harvest" ? "ตัด" : "บำรุง";
      and.push({
        OR: [
          { groupKind },
          { caneGroup: { contains: word } },
          { maintainGroup: { contains: word } },
          { harvestGroup: { contains: word } },
        ],
      });
    }
    if (search) {
      and.push({
        OR: [
          { name: { contains: search, mode: "insensitive" } },
          { rootNo: { contains: search, mode: "insensitive" } },
          { sequenceNo: { contains: search, mode: "insensitive" } },
          { farmer: { displayName: { contains: search, mode: "insensitive"} } },
          { farmer: { username: { contains: search, mode: "insensitive" } } },
        ],
      });
    } 

    const filtered: Prisma.PlotWhereInput = { AND: and };
    const cursor = cursorText ? decodeCursor(cursorText) : undefined;
    const where: Prisma.PlotWhereInput =  cursor
     ? {
        AND: [
          filtered,
         {
          OR: [
            { createdAt: { lt: cursor.createdAt } },
            { AND: [{ createdAt: cursor.createdAt }, { id: { lt: cursor.id } }] },
          ],
         },
        ],
     }
     : filtered;

    const [ total, plots ] = await Promise.all ([
      prisma.plot.count({ where: filtered }),
      prisma.plot.findMany ({
        where,
        orderBy: [{ createdAt: "desc" }, { id: "desc" }],
        take: limit + 1,
        select: summarySelect,
      }),
    ]);
    const page = plots.slice(0, limit);
    const outlines = await readBoundaries(page.map((plot) => plot.id));
    const last = page[page.length - 1];
    res.json({
      items: page.map((plot) => ({
        ...plotSummary(plot),
        meta: plotMeta(plot),
        outline: outlines.get(plot.id) ?? [],
      })),
      nextCursor: plots.length > limit && last ? encodeCursor(last.createdAt, last.id) : null,
      total,
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
      const limit = z.coerce.number().int().min(1).max(50_000).default(200).parse(queryText(req.query.limit));
      const season = queryText(req.query.season);
      const years = csv(req.query.years);
      const includeBlank = queryText(req.query.nullYear) === "1";
      const farmerIds = await farmerIdsForList(user, queryText(req.query.farmerId));
      if (farmerIds.length === 0) {
        res.json({ items: [], truncated: false });
        return;
      }
      const rows = await plotsInBox(farmerIds, box, limit+1, {
        seasons: season ? [season] : years,
        includeBlank: season ? false : includeBlank,
      });
      res.json({
        items: rows.slice(0, limit).map((row) => ({
            ...plotSummary({
              ...row,
              farmer: { id:row.farmerId, username: row.username, displayName: row.displayName },
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
    const rows = await overlappingPlots(prisma, measured.ring, body.season, body.plotId);
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
    const body = createPlotBody.parse(req.body);
    const season = body.season ?? body.productionYear ?? "";

    let farmerId = user.id;
    if (user.role === "OFFICER") {
      if (!body.farmerId) throw new HttpError(400, "ต้องเลือกชาวไร่");
      const link = await prisma.farmerCare.findUnique({
        where: {officerId_farmerId: {officerId: user.id, farmerId: body.farmerId } },
      });
      if (!link) throw new HttpError(404, "ไม่พบชาวไร่");
      farmerId = body.farmerId;
    } else if (user.role !== "FARMER") {
      throw new HttpError(403, "เฉพาะชาวไร่ที่สร้างแปลงได้");
    } else if (body.farmerId && body.farmerId !== user.id) {
      throw new HttpError(403, "บันทึกแปลงได้เฉพาะตัวคุณเอง");
    }

    const plotId = body.id;
    const existing = await prisma.plot.findUnique({ where: { id: plotId }, select: { farmerId: true } });
    if (existing) {
      if (existing.farmerId !== farmerId) throw new HttpError(409, "รหัสแปลงนี้ถูกใช้แล้ว");
      res.json(await toDetail(await visiblePlot(user, plotId)));
      return;
    }
    await refuseDeleted("PLOT", plotId);

    const measured = body.survey ? measureSurvey(body.survey, new Date()) : measurePoints(body.points!);
    const surveyedAt = body.survey?.finishedAt ?? new Date();
    await prisma.$transaction(async (tx) => {
      await lockBoundaries(tx);
      await assertFits(tx, measured, farmerId, season);
      await tx.plot.create({
        data: {
          id: plotId,
          farmerId,
          name: body.name,
          variety: body.caneVariety || body.variety,
          season,
          officerName: body.officerName,
          project: body.project,
          caneGroup: body.caneGroup,
          zone: body.zone,
          province: body.province,
          district: body.district,
          subdistrict: body.subdistrict,
          village: body.village,
          rootNo: body.rootNo,
          sequenceNo: body.sequenceNo,
          prevPlotNo: body.prevPlotNo,
          caneType: body.caneType,
          caneVariety: body.caneVariety,
          ownership: body.ownership,
          terrain: body.terrain,
          hasLoss: body.hasLoss,
          lossRai: body.lossRai,
          targetYield: body.targetYield,
          note: body.note,
          groupKind: body.groupKind,
          areaSqm: measured.areaSqm,
          centerLat: measured.center.latitude,
          centerLng: measured.center.longitude,
          surveyedAt,
        },
      });
      await writeBoundary(tx, plotId, measured.ring);
      if (body.survey) {
        await tx.plotSurvey.create({ data: surveyRecord(plotId, body.survey, measured) });
      }
    }, boundaryTx);

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


  
    const plotRequestBody = z.object({
      kind: z.enum(["status", "edit", "group"]),
      value: z.string().trim().min(1).max(200).optional(),
      reason: z.string().trim().max(200).optional(),
      canePlantMode: z.string().trim().max(80).optional(),
      caneTypeNew: z.string().trim().max(80).optional(),
      newPlotCode: z.string().trim().regex(/^\d{1,10}$/, "รหัสแปลงต้องเป็นตัวเลข").optional(),
      newFarmer: z.string().trim().max(120).optional(),
      newFarmerId: z.string().trim().min(1).max(64).optional(),
      maintainGroup: z.string().trim().max(120).optional(),
      harvestGroup: z.string().trim().max(120).optional(),
    });

  fieldRouter.post(
    "/plots/:plotId/requests",
    route(async (req, res) => {
      const user = currentUser(req);
      const plotId = pathId(req.params.plotId);
      await visiblePlot(user, plotId);
      const body = plotRequestBody.parse(req.body);
      if (body.kind === "status") {
        if (!body.value) throw new HttpError(400, "ยังไม่ได้เลือกสถานะ");
        const allowed = await prisma.fromOption.findUnique({
          where: { group_label: { group: "plotStatuses", label: body.value } },
        });
        if (!allowed) throw new HttpError(400, "สถานะไม่อยู่ในตัวเลือก");
      }
      if (body.kind === "group") {
        if (!body.maintainGroup && !body.harvestGroup) {
          throw new HttpError(400, "ยังไม่ได้เลือกกลุ่ม");
        }
        for (const label of [body.maintainGroup, body.harvestGroup]) {
          if (!label) continue;
          const allowed = await prisma.fromOption.findUnique({
            where: { group_label: { group: "caneGroups", label } },
          });
          if (!allowed) throw new HttpError(400, "กลุ่มไม่อยู่ในตัวเลือก");
        }
      }
      const payload = Object.fromEntries(
        Object.entries({
          value: body.value,
          reason: body.reason,
          canePlantMode: body.canePlantMode,
          caneTypeNew: body.caneTypeNew,
          newPlotCode: body.newPlotCode,
          newFarmer: body.newFarmer,
          newFarmerId: body.newFarmerId,
          maintainGroup: body.maintainGroup,
          harvestGroup: body.harvestGroup,
        }).filter((entry) => entry[1] !== undefined),
      );
      const created = await prisma.plotRequest.create({
        data: {
          plotId,
          kind: body.kind,
          value: body.value ?? "",
          status: "รออนุมัติ",
          requester: user.displayName,
          payload,
        },
      });
      res.status(201).json({ id: created.id, kind: created.kind, value: created.value, status: created.status });
    }),
  );

  fieldRouter.get(
    "/plot-requests",
    route(async (req, res) => {
      const farmerIds = await farmerIdsForList(currentUser(req), undefined);
      if (farmerIds.length === 0) {
        res.json({ items: [] } );
        return;
      }
      const rows = await prisma.plotRequest.findMany({
        where: { plot: { farmerId: {in: farmerIds } } },
        orderBy: { createdAt: "desc" },
        include: { plot: { select: { name: true, season: true } } },
      });
      const outlines = await readBoundaries(rows.map((row) => row.plotId));
      res.json({
       items: rows.map((row) => plotRequestJson(row, outlines.get(row.plotId) ?? [])),
      });
    }),
  );

function payloadText(payload: unknown, key: string): string | undefined {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return undefined;
  const value = (payload as Record<string, unknown>)[key];
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
}
  
function plotRequestJson(
  row: {
    id: string;
    plotId: string;
    kind: string;
    status: string;
    requester: string | null;
    payload: unknown;
    createdAt: Date;
    plot: { name: string; season: string };
  },
  outline: LatLng[],
) {
  return {
    id: row.id,
    plotId: row.plotId,
    plotName: row.plot.name,
    productionYear: row.plot.season === "" ? null : row.plot.season,
    requester: row.requester,
    kind: row.kind,
    payload: row.payload ?? {},
    status: row.status,
    createdAt: row.createdAt.toISOString(),
    outline,
  };
}
 
fieldRouter.patch(
  "/plot-requests/:requestId",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "OFFICER") throw new HttpError(403, "เฉพาะเจ้าหน้าที่ที่เปลี่ยนสถานะคำขอได้");
    const requestId = pathId(req.params.requestId);
    const body = z.object({ status: z.string().trim().min(1).max(80) }).parse(req.body);
    const allowed = await prisma.fromOption.findUnique({
      where: { group_label: { group: "parcelStatuses", label: body.status } },
    });
    if (!allowed) throw new HttpError(400, "สถานะไม่อยู่ในตัวเลือก");

    const existing = await prisma.plotRequest.findUnique({
      where: { id: requestId },
      include: { plot: { select: {name: true, season: true , farmerId: true } } },
    });
    if (!existing) throw new HttpError(404, "ไม่พบคำขอ");
    if (existing.status !== "รออนุมัติ") throw new HttpError(409, "คำขอนี้ตัดสินไปแล้ว");
    await visiblePlot(user, existing.plotId);

    const saved = await prisma.$transaction(async (tx) => {
      const locked = await tx.plotRequest.updateMany({
        where: { id: requestId, status: "รออนุมัติ" },
        data: { status: body.status },
      });
      if (locked.count === 0) throw new HttpError(409, "คำขอนี้ตัดสินไปแล้ว");
      const updated = await tx.plotRequest.findUniqueOrThrow({
        where: { id: requestId },
        include: { plot: { select: { name: true, season: true } } },
      });
      if (body.status === "อนุมัติ" && existing.kind === "status" && existing.value) {
        await tx.plot.update({
          where: { id: existing.plotId },
          data: { status: existing.value, version: { increment: 1 } },
        });
      }
      if (body.status === "อนุมัติ" && existing.kind === "edit") {
      const caneType = payloadText(existing.payload, "caneTypeNew");
      const farmerId = payloadText(existing.payload, "newFarmerId");
      const code = payloadText(existing.payload, "newPlotCode");
      if (farmerId) {
        const farmer = await tx.user.findUnique({ where: { id: farmerId } });
        if (!farmer || farmer.role !== "FARMER") throw new HttpError(400, "ไม่พบชาวไร่คนใหม่");
        const link = await tx.farmerCare.findUnique({
          where: { officerId_farmerId: { officerId: user.id, farmerId } },
        });
        if (!link) throw new HttpError(400, "ชาวไร่คนนี้ไม่อยู่ในความดูแล");
      }
      if (farmerId && farmerId !== existing.plot.farmerId) {
        await tx.deletedRecord.upsert({
          where: {kind_recordId: {kind: "PLOT", recordId: existing.plotId } },
          create: {
            kind: "PLOT",
            recordId: existing.plotId,
            farmerId: existing.plot.farmerId,
            season: existing.plot.season,
          },
          update: {
            farmerId: existing.plot.farmerId,
            season: existing.plot.season,
            deletedAt: new Date(),
          },
        });
      }
      if (caneType || farmerId || code) {
        const land = existing.plot.name.replace(/\s*#\d+\s*$/, "");
        await tx.plot.update({
          where: { id: existing.plotId },
          data: {
            caneType,
            name: code ? `${land} #${code}` : undefined,
            farmer: farmerId ? { connect: { id: farmerId } } : undefined,
            version: { increment: 1 },
          },
        });
      }
     }
     if (body.status === "อนุมัติ" && existing.kind === "group") {
      const maintainGroup = payloadText(existing.payload, "maintainGroup");
      const harvestGroup = payloadText(existing.payload, "harvestGroup");
      if (maintainGroup || harvestGroup) {
        await tx.plot.update({
          where: { id: existing.plotId },
          data: {
            maintainGroup,
            harvestGroup,
            version: {increment: 1 },
          },
        });
      }
     }
      return updated;
    });

    const outlines = await readBoundaries([saved.plotId]);
    res.json(plotRequestJson(saved, outlines.get(saved.plotId) ?? []));
  }),
);

fieldRouter.patch(
  "/plots/:plotId",
  route(async (req, res) => {
    const user = currentUser(req);
    const plotId = pathId(req.params.plotId);
    const plot = await ownedPlot(user, plotId);
    const body = updatePlotBody.parse(req.body);
    const survey = body.survey;
    const measured = survey ? measureSurvey(survey, new Date()) : undefined;
    

    const saved = await prisma.$transaction(async (tx) => {
      if (measured) await lockBoundaries(tx);
      const data = {
        name: body.name,
        variety: body.caneVariety || body.variety,
        officerName: body.officerName,
        project: body.project,
        caneGroup: body.caneGroup,
        zone: body.zone,
        province: body.province,
        district: body.district,
        subdistrict: body.subdistrict,
        village: body.village,
        rootNo: body.rootNo,
        sequenceNo: body.sequenceNo,
        prevPlotNo: body.prevPlotNo,
        caneType: body.caneType,
        caneVariety: body.caneVariety,
        ownership: body.ownership,
        terrain: body.terrain,
        hasLoss: body.hasLoss,
        lossRai: body.lossRai,
        targetYield: body.targetYield,
        note: body.note,
        groupKind: body.groupKind,
        cutStatus: body.cutStatus,
        areaSqm: measured?.areaSqm,
        centerLat: measured?.center.latitude,
        centerLng: measured?.center.longitude,
        surveyedAt: survey?.finishedAt,
        version: { increment: 1 },
      };
     const updated = await tx.plot.updateMany({ where: { id: plotId, version: body.version }, data });
     if (updated.count === 0) return false;
      if (survey && measured) {
        await assertFits(tx, measured, plot.farmerId, plot.season, plotId);
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

    const plot = await prisma.plot.findUnique({
      where: { id: plotId },
      select: { farmerId: true, season: true },
    });
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
      await tx.deletedRecord.upsert({
        where: {kind_recordId: {kind: "PLOT", recordId: plotId } },
        create: { kind: "PLOT", recordId: plotId, farmerId: user.id, season: plot.season },
        update: { farmerId: user.id, season: plot.season, deletedAt: new Date() },
      });
      return true;
    });
    if (!removed) throw versionConflict(await toDetail(await visiblePlot(user, plotId)));
    res.status(204).send();
  }),
);

const activityBody = z
 .object({
  id: z.string().trim().min(1).max(80).optional(),
  plantedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  detailPending: z.boolean().default(false),
  photoCount: z.number().int().min(0).max(3).default(0),
 })
 .passthrough();

const updateActivityBody = z
.object({
  version: baseVersion,
  plantedAt: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  detailPending: z.boolean().optional(),
  photoCount: z.number().int().min(0).max(3).optional(),
})
.passthrough()
.refine((value) => Object.keys(value).some((key) => key !== "version"), {
  message: "ไม่มีข้อมูลที่ให้แก้ไข",
});

fieldRouter.get(
  "/activities",
  route(async (req, res) => {
    const limit = z.coerce.number().int().min(1).max(50).default(30).parse(queryText(req.query.limit));
    const cursorText = queryText(req.query.cursor);
    const farmerIds = await farmerIdsForList(currentUser(req), undefined);
    if (farmerIds.length === 0 ) {
      res.json({ items: [], nextCursor: null });
      return;
    }
    const cursor = cursorText ? decodeCursor(cursorText) : undefined;
    const where: Prisma.PlotActivityWhereInput = {
      plot: { farmerId: { in: farmerIds } },
      ...(cursor 
        ? {
          OR: [
            {createdAt: { lt: cursor.createdAt } },
            { AND: [{ createdAt: cursor.createdAt }, { id: { lt: cursor.id } }] },
          ],
        }
      : {}),
    };
    const rows = await prisma.plotActivity.findMany({
      where,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });
    const page = rows.slice(0, limit);
    const last = page[page.length - 1];
    res.json({
      items: page.map(activityJson),
      nextCursor: rows.length > limit && last ? encodeCursor(last.createdAt, last.id) : null,
    });
  }),
);

fieldRouter.get(
  "/plots/:plotId/activities",
  route(async (req, res) => {
    const plot = await visiblePlot(currentUser(req), pathId(req.params.plotId));
    const rows = await prisma.plotActivity.findMany({
      where: { plotId: plot.id },
      orderBy: { createdAt: "desc" },
    });
    res.json({ items: rows.map(activityJson) });
  }),
);

fieldRouter.post(
  "/plots/:plotId/activities",
  route(async (req, res) => {
    const plot = await ownedPlot(currentUser(req), pathId(req.params.plotId));
    const body = activityBody.parse(req.body);
    const { id, plantedAt: plantedAtText, detailPending, photoCount, ...rest } = body;
    const activityId = id ?? randomUUID();
    const plantedAt = plantedAtText ? parseDate(plantedAtText) : null;
    const detail = Object.fromEntries(
      Object.entries(rest).filter(([, value]) => value !== undefined && value !== null && value !== ""),
    );

    if (id) {
      const existing = await prisma.plotActivity.findUnique({ where: { id } });
      if (existing) {
        if (existing.plotId !== plot.id) throw new HttpError(409, "รหัสกิจกรรมนี้ถูกใช้แล้ว");
        res.json(activityJson(existing));
        return;
      }
      await refuseDeleted("ACTIVITY", id);
    }

    const saved = await prisma.$transaction(async (tx) => {
      const created = await tx.plotActivity.create({
        data: {
          id: activityId,
          plotId: plot.id,
          plantedAt,
          detailPending,
          photoCount,
          detail: detail as Prisma.InputJsonValue,
        },
      });
      if (plantedAt) {
        await tx.plot.update({
          where: { id: plot.id },
          data: {  plantedAt, version: { increment: 1 } },
        });
      }
      return created;
    });
    res.status(201).json(activityJson(saved));
  }),
);

fieldRouter.patch(
  "/activities/:activityId",
  route(async (req, res) => {
    const activityId = pathId(req.params.activityId);
    const existing = await prisma.plotActivity.findUnique({ where: { id: activityId } });
    if (!existing) {
      await refuseDeleted("ACTIVITY", activityId);
      throw new HttpError(404, "ไม่พบกิจกรรม");
    }
    const plot = await ownedPlot(currentUser(req), existing.plotId);
    const body = updateActivityBody.parse(req.body);
    const { version, plantedAt: plantedAtText, detailPending, photoCount, ...rest } = body;
    const plantedAt = plantedAtText ? parseDate(plantedAtText) : undefined;
    const incoming = Object.fromEntries(
      Object.entries(rest).filter(([, value]) => value !== undefined && value !== null && value !== ""),
    );
    const previous =
      existing.detail && typeof existing.detail === "object" && !Array.isArray(existing.detail)
        ? (existing.detail as Record<string, unknown>)
        : {};
    const detail = Object.keys(incoming).length > 0 ? { ...previous, ...incoming } : undefined;

    const saved = await prisma.$transaction(async (tx) => {
      const updated = await tx.plotActivity.updateMany({
        where: { id: activityId, version },
        data: {
          plantedAt,
          detailPending,
          photoCount,
          detail: detail as Prisma.InputJsonValue | undefined,
          version: { increment: 1 }
        },
      });
      if (updated.count === 0) return null;
      if (plantedAt) {
        await tx.plot.update({
          where: { id: plot.id },
          data: { plantedAt, version: { increment: 1 } },
        });
      }
      return tx.plotActivity.findUniqueOrThrow({ where: { id: activityId } });
    });
    if (!saved) {
      const current = await prisma.plotActivity.findUniqueOrThrow({ where: { id: activityId } });
      throw versionConflict(activityJson(current));
    }
    res.json(activityJson(saved));
  }),
);

fieldRouter.delete(
  "/activities/:activityId",
  route(async (req, res) => {
    const user = currentUser(req);
    const activityId = pathId(req.params.activityId);
    const version = versionQuery(req.query.version);
    const existing = await prisma.plotActivity.findUnique({ where: { id: activityId } });
    if (!existing) {
      if (await wasDeletedBy("ACTIVITY", activityId, user.id)) {
        res.status(204).send();
        return;
      }
      throw new HttpError(404, "ไม่พบกิจกรรม");
    }
    const plot = await ownedPlot(user, existing.plotId);

    const removed = await prisma.$transaction(async (tx) => {
      const result = await tx.plotActivity.deleteMany({
        where: { id: activityId, ...(version ? { version } : {}) },
      });
      if (result.count === 0) return false;
      await tx.deletedRecord.create({
        data: {
          kind: "ACTIVITY",
          recordId: activityId,
          farmerId: plot.farmerId,
          plotId: plot.id,
          season: plot.season,
        },
      });
      return true;
    });
    if (!removed) {
      const current = await prisma.plotActivity.findUniqueOrThrow({ where: { id: activityId } });
      throw versionConflict(activityJson(current));
    }
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
        data: { kind: "YIELD", recordId: yieldId, farmerId: user.id, plotId: plot.id, season: plot.season },
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
        data: { kind: "TASK", recordId: taskId, farmerId: user.id, plotId: plot.id, season: plot.season },
      });
      return true;
    });
    if (!removed) throw versionConflict(taskJson(await prisma.fieldTask.findUniqueOrThrow({ where: { id: taskId } })));
    res.status(204).send();
  }),
);

function riskJson(row: {
  plotId: string;
  type: string;
  name: string | null;
  note: string | null;
  severity: number | null;
  updatedAt: Date;
}) {
  return{
    plotId: row.plotId,
    type: row.type,
    name: row.name,
    severity: row.severity,
    note: row.note,
    updatedAt: row.updatedAt.toISOString(),
  };
}

const riskBody = z.object({
  type: z.string().trim().min(1).max(80),
  name: z.string().trim().max(200).nullish(),
  note: z.string().trim().max(500).nullish(),
  severity: z.number().int().min(1).max(5).nullish(),
});

fieldRouter.get(
  "/risk-points",
  route(async (req, res) => {
    const farmerIds = await farmerIdsForList(currentUser(req), undefined);
    if (farmerIds.length === 0) {
      res.json({ items: [] });
      return;
    }
    const rows = await prisma.riskPoint.findMany({
      where: { plot: { farmerId: { in: farmerIds } } },
    });
    res.json({ items: rows.map(riskJson) });
  }),
);

fieldRouter.put(
  "/plots/:plotId/risk-point",
  route(async (req, res) => {
    const plot = await ownedPlot(currentUser(req), pathId(req.params.plotId));
    const body = riskBody.parse(req.body);
    const existing = await prisma.fromOption.findUnique({
      where: { group_label: { group: "riskLevels", label: body.type } },
    });
    if (!existing) throw new HttpError(400, "ประเภทจุดเสี่ยงไม่อยู่ในตัวเลือก");

    const row = await prisma.riskPoint.upsert({
      where: { plotId: plot.id },
      create: {
        plotId: plot.id,
        type: body.type,
        name: body.name ?? null,
        note: body.note ?? null,
        severity: body.severity ?? null,
      },
      update: {
        type: body.type,
        name: body.name ?? null,
        note: body.note ?? null,
        severity: body.severity ?? null,
      },
    });
    res.json(riskJson(row));
  })
)
