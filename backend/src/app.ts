import compression from "compression";
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
  // gzip ทุก response — JSON แปลงหลายพันตัวหดเหลือ ~10-20%
  // สำคัญมากบนเน็ตแปลงจริง (3G/4G อ่อน)
  // ข้าม route ที่ gzip เองแล้ว (set Content-Encoding มาแล้ว)
  app.use(
    compression({
      filter: (req, res) =>
        res.getHeader("Content-Encoding") == null &&
        compression.filter(req, res),
    }),
  );
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
