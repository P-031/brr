import { HttpError } from "./http";

type Cursor = {
  createdAt: Date;
  id: string;
};

export function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(JSON.stringify({ createdAt: createdAt.toISOString(), id }), "utf8").toString("base64url");
}

export function decodeCursor(value: string): Cursor {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
    if (
      !parsed ||
      typeof parsed !== "object" ||
      !("createdAt" in parsed) ||
      !("id" in parsed) ||
      typeof parsed.createdAt !== "string" ||
      typeof parsed.id !== "string" ||
      parsed.id.length === 0
    ) {
      throw new Error("shape");
    }
    const createdAt = new Date(parsed.createdAt);
    if (Number.isNaN(createdAt.getTime())) throw new Error("date");
    return { createdAt, id: parsed.id };
  } catch {
    throw new HttpError(400, "cursor ไม่ถูกต้อง");
  }
}
