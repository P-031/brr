import cors from "cors";
import express from "express";
import { requireAuth } from "./auth";
import { errorHandler } from "./http";
import { accountRouter } from "./routes/account";
import { fieldRouter } from "./routes/plots";
import { sessionRouter } from "./routes/session";
import { syncRouter } from "./routes/sync";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use(cors());
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.use(sessionRouter);
  app.use(requireAuth);
  app.use(accountRouter);
  app.use(fieldRouter);
  app.use(syncRouter);
  app.use((_req, res) => {
    res.status(404).json({ error: "ไม่พบเส้นทาง" });
  });
  app.use(errorHandler);
  return app;
}
