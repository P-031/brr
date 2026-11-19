import { Router } from "express";
import { RateLimiterMemory, RateLimiterRedis } from "rate-limiter-flexible";
import { z } from "zod";
import { currentUser } from "../auth";
import { HttpError, route } from "../http";
import { resetUserPassword, verifyUserPassword } from "../keycloak";
import { prisma } from "../prisma";
import { redis } from "../redis";
import { publicProfile } from "../serialize";

export const accountRouter = Router();

const linkBody = z
  .object({
    farmerId: z.string().trim().min(1).max(64).optional(),
    username: z.string().trim().min(1).max(120).optional(),
  })
  .refine((value) => value.farmerId !== undefined || value.username !== undefined, {
    message: "ต้องระบุ farmerId หรือ username",
  });

accountRouter.get(
  "/me",
  route(async (req, res) => {
    const user = currentUser(req);
    res.json({ ...publicProfile(user), keycloakId: user.keycloakId });
  }),
);

const passwordBody = z.object({
  currentPassword: z.string().min(1, "ต้องระบุรหัสผ่านเดิม"),
  newPassword: z.string().min(6, "รหัสผ่านใหม่ต้องยาวอย่างน้อย 6 ตัว").max(128),
});

// Each attempt costs a Keycloak direct-grant call — cap how often a
// user can retry so this endpoint can't brute-force passwords.
const passwordLimiter = (() => {
  const r = redis();
  const opts = { points: 5, duration: 60, keyPrefix: "rl:pw" };
  return r
    ? new RateLimiterRedis({ storeClient: r, ...opts })
    : new RateLimiterMemory(opts);
})();

// Verifies the old password against Keycloak before resetting —
// Admin API callers can't read user passwords back, so direct grant
// doubles as the credential check.
accountRouter.put(
  "/me/password",
  route(async (req, res) => {
    const user = currentUser(req);
    try {
      await passwordLimiter.consume(user.id);
    } catch {
      throw new HttpError(429, "ลองใหม่อีกครั้งภายหลัง");
    }
    const body = passwordBody.parse(req.body);
    await verifyUserPassword(user.username, body.currentPassword);
    await resetUserPassword(user.keycloakId, body.newPassword);
    res.status(204).send();
  }),
);

accountRouter.get(
  "/officers",
  route(async (req, res) => {
    const user = currentUser(req);

    if (user.role === "FARMER") {
      const links = await prisma.farmerCare.findMany({
        where: { farmerId: user.id },
        orderBy: { createdAt: "asc" },
        include: { officer: true },
      });
      res.json({ items: links.map((link) => publicProfile(link.officer)) });
      return;
    }

    const officers = await prisma.user.findMany({
      where: { role: "OFFICER" },
      orderBy: { displayName: "asc" },
    });
    res.json({ items: officers.map(publicProfile) });
  }),
);

accountRouter.get(
  "/officers",
  route(async (_req, res) => {
    const officers = await prisma.user.findMany({
      where: { role: "OFFICER"},
      orderBy: { displayName: "asc" },
    });
    res.json({ items: officers.map(publicProfile) });
  }),
);

accountRouter.get(
  "/farmers",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "OFFICER") throw new HttpError(403, "เฉพาะนักส่งเสริม");

    const [farmers, links] = await Promise.all([
      prisma.user.findMany({
        where: { role: "FARMER" },
        orderBy: { displayName: "asc" },
      }),
      prisma.farmerCare.findMany({ where: { officerId: user.id } }),
    ]);
    const since = new Map(links.map((link) => [link.farmerId, link.createdAt.toISOString()]));

    res.json({
      items: farmers.map((farmer) => ({
        ...publicProfile(farmer),
        since: since.get(farmer.id) ?? null,
      })),
    });
  }),
);

accountRouter.post(
  "/farmers",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "OFFICER") throw new HttpError(403, "เฉพาะนักส่งเสริม");

    const body = linkBody.parse(req.body);
    const farmer = body.farmerId
      ? await prisma.user.findUnique({ where: { id: body.farmerId } })
      : await prisma.user.findUnique({ where: { username: body.username } });

    if (!farmer || farmer.role !== "FARMER") throw new HttpError(404, "ไม่พบชาวไร่");

    const existing = await prisma.farmerCare.findUnique({
      where: { officerId_farmerId: { officerId: user.id, farmerId: farmer.id } },
    });
    const link =
      existing ??
      (await prisma.farmerCare.create({
        data: { officerId: user.id, farmerId: farmer.id },
      }));

    res.status(existing ? 200 : 201).json({
      ...publicProfile(farmer),
      since: link.createdAt.toISOString(),
    });
  }),
);

accountRouter.delete(
  "/farmers/:farmerId",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "OFFICER") throw new HttpError(403, "เฉพาะนักส่งเสริม");

    const farmerId = z.string().min(1).parse(req.params.farmerId);
    const removed = await prisma.farmerCare.deleteMany({
      where: { officerId: user.id, farmerId },
    });
    if (removed.count === 0) throw new HttpError(404, "ไม่พบชาวไร่ในความดูแล");
    res.status(204).send();
  }),
);
