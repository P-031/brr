import { Prisma } from "@prisma/client";
import { Router, type Request, type Response } from "express";
import { gunzipSync, gzipSync } from "zlib";
import { z } from "zod";
import { currentUser } from "../auth";
import { normalizeRing, polygonAreaSqm, ringCenter, type LatLng } from "../area";
import { plotsInBox, readBoundary, ringFromGeoJson, writeBoundary } from "../boundary";
import { decodeCursor, encodeCursor } from "../cursor";
import { HttpError, route } from "../http";
import { enqueuePlotEvent } from "../jobs";
import { prisma } from "../prisma";
import { cacheDelPattern, cacheGetRaw, cacheSetRaw } from "../redis";
import { plotDetail, plotSummary, taskJson, taskKindByName, yieldJson } from "../serialize";
import type { AuthUser } from "../types";

/// gzip เองเพื่อใส่ Content-Length — compression middleware ส่ง
/// chunked ไม่บอกขนาด ทำให้แอปคำนวณ % ดาวน์โหลดไม่ได้
/// (app.ts มี filter ข้าม compression อัตโนมัติเมื่อ set
/// Content-Encoding ไว้แล้ว)
function sendJson(req: Request, res: Response, payload: unknown) {
  const acceptsGzip = String(req.headers["accept-encoding"] ?? "").includes("gzip");
  if (acceptsGzip) {
    sendGzipped(req, res, gzipSync(JSON.stringify(payload)));
    return;
  }
  res.json(payload);
}

/// ส่ง buffer ที่ gzip ไว้แล้ว — client ไม่รับ gzip ก็ gunzip คืน
/// JSON ดิบให้ (กรณีหายาก — แอปเราส่ง Accept-Encoding: gzip เสมอ)
function sendGzipped(req: Request, res: Response, gz: Buffer) {
  const acceptsGzip = String(req.headers["accept-encoding"] ?? "").includes("gzip");
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  if (acceptsGzip) {
    res.setHeader("Content-Encoding", "gzip");
    res.setHeader("Content-Length", gz.length);
    res.end(gz);
    return;
  }
  const raw = gunzipSync(gz);
  res.setHeader("Content-Length", raw.length);
  res.end(raw);
}

const pointSchema = z.object({
  latitude: z.number().finite().gte(-90).lte(90),
  longitude: z.number().finite().gte(-180).lte(180),
});

const pointsSchema = z.array(pointSchema).min(3).max(2000);

const metaString = (max = 160) => z.string().trim().max(max).optional();
const metaNumber = () => z.number().finite().nonnegative().optional();

const createPlotBody = z.object({
  name: z.string().trim().min(1).max(120),
  variety: z.string().trim().max(120).default(""),
  // Officer-created plots belong to a farmer under their care.
  farmerId: z.string().trim().min(1).optional(),
  // Measurement-form metadata saved with the plot.
  productionYear: metaString(20),
  officerName: metaString(),
  project: metaString(),
  caneGroup: metaString(),
  zone: metaString(60),
  province: metaString(60),
  district: metaString(60),
  subdistrict: metaString(60),
  village: metaString(80),
  rootNo: metaString(30),
  sequenceNo: metaString(30),
  prevPlotNo: metaString(60),
  caneType: metaString(80),
  caneVariety: metaString(80),
  ownership: metaString(60),
  terrain: metaString(60),
  hasLoss: metaString(200),
  lossRai: metaNumber(),
  targetYield: metaNumber(),
  note: metaString(500),
  points: pointsSchema,
});

const updatePlotBody = z
  .object({
    name: z.string().trim().min(1).max(120).optional(),
    variety: z.string().trim().max(120).optional(),
    productionYear: metaString(20),
    officerName: metaString(),
    project: metaString(),
    caneGroup: metaString(),
    zone: metaString(60),
    province: metaString(60),
    district: metaString(60),
    subdistrict: metaString(60),
    village: metaString(80),
    rootNo: metaString(30),
    sequenceNo: metaString(30),
    prevPlotNo: metaString(60),
    caneType: metaString(80),
    caneVariety: metaString(80),
    ownership: metaString(60),
    terrain: metaString(60),
    hasLoss: metaString(200),
    lossRai: metaNumber(),
    targetYield: metaNumber(),
    note: metaString(500),
    points: pointsSchema.optional(),
  })
  .refine((value) => Object.values(value).some((v) => v !== undefined), {
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
  productionYear: true,
  officerName: true,
  project: true,
  caneGroup: true,
  zone: true,
  province: true,
  district: true,
  subdistrict: true,
  village: true,
  rootNo: true,
  sequenceNo: true,
  prevPlotNo: true,
  caneType: true,
  caneVariety: true,
  ownership: true,
  terrain: true,
  hasLoss: true,
  lossRai: true,
  targetYield: true,
  note: true,
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

/** Who the new plot belongs to: the farmer themself, or any farmer the
 *  officer picked — first save silently links that farmer to the
 *  officer's care so the new plot stays visible to them. */
async function plotOwnerForCreate(user: AuthUser, requestedFarmerId: string | undefined): Promise<string> {
  if (user.role === "FARMER") return user.id;
  if (!requestedFarmerId) throw new HttpError(400, "ต้องระบุชาวไร่เจ้าของแปลง");
  const farmer = await prisma.user.findUnique({ where: { id: requestedFarmerId } });
  if (!farmer || farmer.role !== "FARMER") throw new HttpError(404, "ไม่พบชาวไร่");
  await prisma.farmerCare.upsert({
    where: { officerId_farmerId: { officerId: user.id, farmerId: requestedFarmerId } },
    create: { officerId: user.id, farmerId: requestedFarmerId },
    update: {},
  });
  return requestedFarmerId;
}

async function ownedPlot(user: AuthUser, plotId: string) {
  const plot = await prisma.plot.findUnique({ where: { id: plotId } });
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
        limit: z.coerce.number().int().min(1).max(2000).default(20),
        cursor: z.string().min(1).optional(),
        farmerId: z.string().min(1).optional(),
        zone: z.string().min(1).optional(),
        caneType: z.string().min(1).optional(),
        planted: z.enum(["0", "1"]).optional(),
        groupKind: z.enum(["harvest", "maintain"]).optional(),
        search: z.string().min(1).optional(),
      })
      .parse({
        limit: queryText(req.query.limit),
        cursor: queryText(req.query.cursor),
        farmerId: queryText(req.query.farmerId),
        zone: queryText(req.query.zone),
        caneType: queryText(req.query.caneType),
        planted: queryText(req.query.planted),
        groupKind: queryText(req.query.groupKind),
        search: queryText(req.query.search),
      });

    const farmerIds = await farmerIdsForList(user, query.farmerId);
    if (farmerIds.length === 0) {
      res.json({ items: [], nextCursor: null });
      return;
    }

    // กรองปีแบบเดียวกับ /plots/map — years=2567,2568 + nullYear=1
    const yearList = queryText(req.query.years);
    const years =
      yearList === undefined
        ? undefined
        : [
            ...yearList.split(",").map((y) => y.trim()).filter(Boolean),
            ...(queryText(req.query.nullYear) === "1" ? [null] : []),
          ];
    if (years !== undefined && years.length === 0) {
      res.json({ items: [], nextCursor: null });
      return;
    }
    const namedYears = years?.filter((y): y is string => y != null) ?? [];

    const cursor = query.cursor ? decodeCursor(query.cursor) : undefined;
    const baseWhere: Prisma.PlotWhereInput = {
      farmerId: { in: farmerIds },
      // สถานะปลูก = มีประเภทอ้อยบันทึกไว้ (caneType) — แปลงที่ยังไม่
      // ลงประเภทถือว่ายังไม่ปลูก
      ...(query.planted === "1"
        ? { AND: [{ caneType: { not: null } }, { caneType: { not: "" } }] }
        : query.planted === "0"
          ? { OR: [{ caneType: null }, { caneType: "" }] }
          : {}),
      // กลุ่มตัด/กลุ่มบำรุง = คัดจากชื่อกลุ่มที่มีคำนั้น
      ...(query.groupKind === "harvest"
        ? { caneGroup: { contains: "ตัด" } }
        : query.groupKind === "maintain"
          ? { caneGroup: { contains: "บำรุง" } }
          : {}),
      // zone/caneType รับหลายค่าคั่น comma — เลือกได้มากกว่า 1
      ...(query.zone
        ? { zone: { in: query.zone.split(",").map((z) => z.trim()).filter(Boolean) } }
        : {}),
      ...(query.caneType
        ? {
            caneType: {
              in: query.caneType.split(",").map((t) => t.trim()).filter(Boolean),
            },
          }
        : {}),
      // ค้นหาจากชื่อแปลง / รหัสพื้นที่ (ลำดับ-รูท) / รหัส-ชื่อชาวไร่
      ...(query.search
        ? {
            OR: [
              { name: { contains: query.search, mode: "insensitive" } },
              { sequenceNo: { contains: query.search } },
              { rootNo: { contains: query.search } },
              {
                farmer: {
                  is: {
                    OR: [
                      { username: { contains: query.search, mode: "insensitive" } },
                      { displayName: { contains: query.search, mode: "insensitive" } },
                    ],
                  },
                },
              },
            ],
          }
        : {}),
      ...(years === undefined
        ? {}
        : {
            OR: [
              ...(namedYears.length > 0
                ? [{ productionYear: { in: namedYears } }]
                : []),
              ...(years.includes(null)
                ? [{ productionYear: null }, { productionYear: "" }]
                : []),
            ],
          }),
    };
    const [plots, total] = await Promise.all([
      prisma.plot.findMany({
        where: {
          ...baseWhere,
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
      }),
      // จำนวนรวมตามฟิลเตอร์ — ปุ่ม "แสดงผลบนแผนที่" ในแอปโชว์ค่านี้
      prisma.plot.count({ where: baseWhere }),
    ]);

    const page = plots.slice(0, query.limit);
    const last = page[page.length - 1];
    // outline ของแปลงในหน้านี้ — query เดียวพอ (≤30 แปลง) สำหรับ
    // thumbnail สี่เหลี่ยมหน้าการ์ด; 5 ตำแหน่งทศนิยมพอให้รูปเดิม
    const outlineRows =
      page.length === 0
        ? []
        : await prisma.$queryRaw<Array<{ id: string; geojson: string | null }>>`
            SELECT id, ST_AsGeoJSON(boundary, 5) AS geojson
            FROM "Plot"
            WHERE id IN (${Prisma.join(page.map((p) => p.id))})
          `;
    const outlineById = new Map(outlineRows.map((r) => [r.id, ringFromGeoJson(r.geojson)]));
    res.json({
      items: page.map((p) => ({ ...plotSummary(p), outline: outlineById.get(p.id) ?? [] })),
      nextCursor: plots.length > query.limit && last ? encodeCursor(last.createdAt, last.id) : null,
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
    const limit = z.coerce.number().int().min(1).max(50000).default(200).parse(queryText(req.query.limit));
    const farmerFilter = queryText(req.query.farmerId) ?? "";
    // กรองปีฝั่ง SQL — years=2567,2568 (comma-separated); nullYear=1
    // รวมแปลงที่ไม่มีปีด้วย ไม่ส่ง years เลย = ทุกปี
    const yearList = queryText(req.query.years);
    const years =
      yearList === undefined
        ? undefined
        : [
            ...yearList.split(",").map((y) => y.trim()).filter(Boolean),
            ...(queryText(req.query.nullYear) === "1" ? [null] : []),
          ];
    const yearKey = years === undefined ? "*" : years.map((y) => y ?? "null").join(",");
    // :gz = payload ถูก cache เป็น gzip base64 (compress ครั้งเดียว
    // แล้วส่งตรงทุก hit — ไม่ต้อง gzipSync ซ้ำทุก request)
    const cacheKey =
      `plots:map:${user.id}:${box.west},${box.south},${box.east},${box.north}:${limit}:${farmerFilter}:${yearKey}:gz`;
    const cachedGz = await cacheGetRaw(cacheKey);
    if (cachedGz !== undefined) {
      sendGzipped(req, res, Buffer.from(cachedGz, "base64"));
      return;
    }

    const farmerIds = await farmerIdsForList(user, farmerFilter);
    if (farmerIds.length === 0) {
      sendJson(req, res, { items: [], truncated: false });
      return;
    }

    const rows = await plotsInBox(farmerIds, box, limit + 1, years);
    // payload แบบบาง — meta หนักๆ (20 ฟิลด์) ไม่จำเป็นตอน render
    // แผนที่; แอปดึง /plots/:id ทีละตัวตอนผู้ใช้แตะแปลงจริง
    // 40MB → ~15MB: gunzip+parse ในแอปเร็วขึ้นมากบนเครื่องอ่อน
    const payload = {
      items: rows.slice(0, limit).map((row) => ({
        id: row.id,
        name: row.name,
        productionYear: row.productionYear,
        outline: ringFromGeoJson(row.outline),
      })),
      truncated: rows.length > limit,
    };
    const gz = gzipSync(JSON.stringify(payload));
    await cacheSetRaw(cacheKey, gz.toString("base64"), 60);
    sendGzipped(req, res, gz);
  }),
);

/// รายการปีการผลิต + จำนวนแปลง — เบา ใช้ทำหน้าเลือกดาวน์โหลด
/// (ดึงครั้งเดียวแทนที่จะเพจ /plots ทีละหน้า)
fieldRouter.get(
  "/plots/years",
  route(async (req, res) => {
    const user = currentUser(req);
    const farmerIds = await farmerIdsForList(user, queryText(req.query.farmerId));
    if (farmerIds.length === 0) {
      res.json({ items: [] });
      return;
    }
    const rows = await prisma.$queryRaw<
      Array<{ year: string | null; count: bigint }>
    >`
      SELECT p."productionYear" AS year, count(*)::bigint AS count
      FROM "Plot" p
      WHERE p."farmerId" IN (${Prisma.join(farmerIds)})
      GROUP BY p."productionYear"
      ORDER BY year DESC NULLS LAST
    `;
    res.json({
      items: rows.map((r) => ({ year: r.year, count: Number(r.count) })),
    });
  }),
);

fieldRouter.post(
  "/plots",
  route(async (req, res) => {
    const user = currentUser(req);
    const body = createPlotBody.parse(req.body);
    const farmerId = await plotOwnerForCreate(user, body.farmerId);
    const measured = measuredRing(body.points);
    const plotId = await prisma.$transaction(async (tx) => {
      const created = await tx.plot.create({
        data: {
          farmerId,
          name: body.name,
          variety: body.variety,
          productionYear: body.productionYear,
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
          areaSqm: measured.areaSqm,
          centerLat: measured.center.latitude,
          centerLng: measured.center.longitude,
        },
        select: { id: true },
      });
      await writeBoundary(tx, created.id, measured.ring);
      return created.id;
    });

    await cacheDelPattern("plots:map:*");
    await enqueuePlotEvent("plot.created", { userId: user.id, plotId, name: body.name });
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
    const { points, ...meta } = body;

    await prisma.$transaction(async (tx) => {
      await tx.plot.update({
        where: { id: plotId },
        data: {
          ...meta,
          areaSqm: measured?.areaSqm,
          centerLat: measured?.center.latitude,
          centerLng: measured?.center.longitude,
        },
      });
      if (measured) await writeBoundary(tx, plotId, measured.ring);
    });

    await cacheDelPattern("plots:map:*");
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
    await cacheDelPattern("plots:map:*");
    res.status(204).send();
  }),
);

const requestBody = z
  .object({
    kind: z.enum(["status", "edit", "group"]),
    value: metaString(200),
    reason: metaString(),
    maintainGroup: metaString(),
    harvestGroup: metaString(),
    // คำขอ2 "แก้ไขประเภทอ้อย" / "แก้ไขชาวไร"
    canePlantMode: metaString(),
    caneTypeNew: metaString(),
    newPlotCode: metaString(),
    newFarmer: metaString(),
    newFarmerId: metaString(),
  })
  .refine(
    (b) => b.value != null || b.maintainGroup != null || b.harvestGroup != null,
    { message: "ต้องระบุข้อมูลคำขอ" },
  );

fieldRouter.post(
  "/plots/:plotId/requests",
  route(async (req, res) => {
    const user = currentUser(req);
    const plot = await visiblePlot(user, pathId(req.params.plotId));
    const body = requestBody.parse(req.body);
    const request = await prisma.plotRequest.create({
      data: {
        plotId: plot.id,
        userId: user.id,
        kind: body.kind,
        payload: {
          ...(body.value != null ? { value: body.value } : {}),
          ...(body.reason != null ? { reason: body.reason } : {}),
          ...(body.canePlantMode != null ? { canePlantMode: body.canePlantMode } : {}),
          ...(body.caneTypeNew != null ? { caneTypeNew: body.caneTypeNew } : {}),
          ...(body.newPlotCode != null ? { newPlotCode: body.newPlotCode } : {}),
          ...(body.newFarmer != null ? { newFarmer: body.newFarmer } : {}),
          ...(body.newFarmerId != null ? { newFarmerId: body.newFarmerId } : {}),
          ...(body.maintainGroup != null ? { maintainGroup: body.maintainGroup } : {}),
          ...(body.harvestGroup != null ? { harvestGroup: body.harvestGroup } : {}),
        },
      },
    });
    res.status(201).json({ id: request.id, status: request.status });
  }),
);

/// รายการคำขอทั้งหมดที่ผู้ใช้มองเห็น — farmer เห็นของตัวเอง,
/// officer เห็นของตัวเอง + ที่อยู่บนแปลงของชาวไร่ในความดูแล
fieldRouter.get(
  "/plot-requests",
  route(async (req, res) => {
    const user = currentUser(req);
    const items = await prisma.plotRequest.findMany({
      where:
        user.role === "FARMER"
          ? { userId: user.id }
          : {
              OR: [
                { userId: user.id },
                {
                  plot: {
                    farmer: {
                      caretakers: { some: { officerId: user.id } },
                    },
                  },
                },
              ],
            },
      include: {
        plot: { select: { name: true, productionYear: true } },
        user: { select: { displayName: true } },
      },
      orderBy: { createdAt: "desc" },
    });
    // outline ต่อแปลงสำหรับ thumbnail ดาวเทียม/รูป polygon บนการ์ด —
    // query เดียวเหมือน list /plots
    const plotIds = [...new Set(items.map((r) => r.plotId))];
    const outlineRows =
      plotIds.length === 0
        ? []
        : await prisma.$queryRaw<
            Array<{ id: string; geojson: string | null }>
          >`SELECT id, ST_AsGeoJSON(boundary, 5) AS geojson
            FROM "Plot"
            WHERE id IN (${Prisma.join(plotIds)})`;
    const outlineById = new Map(
      outlineRows.map((r) => [r.id, ringFromGeoJson(r.geojson)]),
    );
    res.json({
      items: items.map((r) => ({
        id: r.id,
        plotId: r.plotId,
        plotName: r.plot.name,
        productionYear: r.plot.productionYear,
        requester: r.user.displayName,
        kind: r.kind,
        payload: r.payload,
        status: r.status,
        createdAt: r.createdAt,
        outline: outlineById.get(r.plotId) ?? [],
      })),
    });
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
