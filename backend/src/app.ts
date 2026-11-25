import cors from "cors";
import express from "express";
import { requireAuth } from "./auth";
import { errorHandler } from "./http";
import { accountRouter } from "./routes/account";
import { fieldRouter } from "./routes/plots";
import { sessionRouter } from "./routes/session";
import { syncRouter } from "./routes/sync";
import { metaRouter } from "./routes/meta";
import { rateLimit } from "express-rate-limit";
import { env } from "./env";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "1mb" }));

  app.use(cors({ origin: env.corsOrigins.length ? env.corsOrigins : true, credentials: true }))


  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.use("/api/v1/auth/token", rateLimit({ windowMs: 60_000, max: 10 }));
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
