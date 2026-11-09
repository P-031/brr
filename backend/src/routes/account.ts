import { Router } from "express";
import { z } from "zod";
import { currentUser } from "../auth";
import { HttpError, route } from "../http";
import { prisma } from "../prisma";
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

accountRouter.get(
  "/farmers",
  route(async (req, res) => {
    const user = currentUser(req);
    if (user.role !== "OFFICER") throw new HttpError(403, "เฉพาะนักส่งเสริม");

    const links = await prisma.farmerCare.findMany({
      where: { officerId: user.id },
      orderBy: { createdAt: "asc" },
      include: { farmer: true },
    });

    res.json({
      items: links.map((link) => ({
        ...publicProfile(link.farmer),
        since: link.createdAt.toISOString(),
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
