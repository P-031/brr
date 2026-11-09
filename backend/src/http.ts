import type { NextFunction, Request, Response } from "express";
import { ZodError } from "zod";

function prismaErrorName(error: unknown): { name: string; code?: string } | undefined {
  if (!error || typeof error !== "object" || !("name" in error) || typeof error.name !== "string") return undefined;
  if (!error.name.startsWith("PrismaClient")) return undefined;
  const code = "code" in error && typeof error.code === "string" ? error.code : undefined;
  return { name: error.name, code };
}

export class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export function route(handler: (req: Request, res: Response) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => {
    handler(req, res).catch(next);
  };
}

export function errorHandler(error: unknown, _req: Request, res: Response, _next: NextFunction) {
  if (error instanceof ZodError) {
    res.status(400).json({
      error: "ข้อมูลไม่ถูกต้อง",
      details: error.issues.map((issue) => ({
        path: issue.path.join("."),
        message: issue.message,
      })),
    });
    return;
  }

  if (error instanceof HttpError) {
    res.status(error.status).json({ error: error.message });
    return;
  }

  const prismaError = prismaErrorName(error);
  if (prismaError?.name === "PrismaClientInitializationError") {
    res.status(503).json({ error: "ยังต่อฐานข้อมูลไม่ได้" });
    return;
  }

  if (prismaError?.code === "P2025") {
    res.status(404).json({ error: "ไม่พบข้อมูล" });
    return;
  }

  if (prismaError?.code === "P2002") {
    res.status(409).json({ error: "ข้อมูลซ้ำ" });
    return;
  }

  console.error(error);
  res.status(500).json({ error: "เซิร์ฟเวอร์ขัดข้อง" });
}
