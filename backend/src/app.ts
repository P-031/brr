import cors from "cors";
import express from "express";
import { requireAuth } from "./auth";
import { errorHandler } from "./http";
import { accountRouter } from "./routes/account";
import { metaRouter } from "./routes/meta";
import { fieldRouter } from "./routes/plots";

export function createApp() {
  const app = express();
  app.disable("x-powered-by");
  app.use(cors());
  app.use(express.json({ limit: "1mb" }));

  app.get("/health", (_req, res) => {
    res.json({ ok: true });
  });

  app.use(requireAuth);
  app.use(accountRouter);
  app.use(metaRouter);
  app.use(fieldRouter);
  app.use((_req, res) => {
    res.status(404).json({ error: "ไม่พบเส้นทาง" });
  });
  app.use(errorHandler);
  return app;
}
