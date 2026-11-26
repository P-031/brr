import cors from "cors";
import express from "express";
import { rateLimit } from "express-rate-limit";
import { requireAuth } from "./auth";
import { env } from "./env";
import { errorHandler } from "./http";
import { prisma } from "./prisma";
import { accountRouter } from "./routes/account";
import { fieldRouter } from "./routes/plots";
import { sessionRouter } from "./routes/session";
import { syncRouter } from "./routes/sync";
import { metaRouter } from "./routes/meta";

export function createApp() {
  const app = express();
  if (process.env.TRUST_PROXY === "1") {
    app.set("trust proxy", 1);
  }
  app.disable("x-powered-by");
  app.use((_req, res, next) => {
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("X-Frame-Options", "DENY");
    res.setHeader("Referrer-Policy", "no-referrer");
    next();
  });
  app.use(express.json({ limit: "1mb" }));

  app.use(cors({ origin: env.corsOrigins.length ? env.corsOrigins : true, credentials: true }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });
  app.get("/ready", async (_req, res) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      res.json({ ok: true });
    } catch {
      res.status(503).json({ ok: false, error: "ยังต่อฐานข้อมูลไม่ได้" });
    }
  });

  const authLimit = rateLimit({ windowMs: 60_000, max: 10 });
  app.use("/api/v1/auth/token", authLimit);
  app.use("/api/v1/auth/refresh", authLimit);
  app.use(sessionRouter);
  app.use(requireAuth);
  app.use(accountRouter);
  app.use(metaRouter);
  app.use(fieldRouter);
  app.use(syncRouter);
  app.use((_req, res) => {
    res.status(404).json({ error: "ไม่พบเส้นทาง" });
  });
  app.use(errorHandler);
  return app;
}
