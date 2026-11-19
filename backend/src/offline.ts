import type { RecordKind } from "@prisma/client";
import { z } from "zod";
import { HttpError } from "./http";
import { prisma } from "./prisma";

/** New records get their id on the phone, so a retried upload after a dropped signal cannot create a second copy. */
export const clientId = z.string().uuid();

export const baseVersion = z.number().int().positive();

/** A sync page starts this far before the request so writes still committing are not skipped. */
export const syncOverlapMs = 10_000;

/** Optional on delete. Without it the delete wins over any edit. */
export function versionQuery(value: unknown): number | undefined {
  const picked = Array.isArray(value) ? value[0] : value;
  if (picked === undefined || picked === "") return undefined;
  return z.coerce.number().int().positive().parse(picked);
}

export function versionConflict(current: unknown): HttpError {
  return new HttpError(409, "ข้อมูลถูกแก้จากที่อื่นแล้ว", { code: "VERSION_CONFLICT", current });
}

export async function deletedRecord(kind: RecordKind, recordId: string) {
  return prisma.deletedRecord.findUnique({ where: { kind_recordId: { kind, recordId } } });
}

/** A queued create that reaches the server after the record was deleted must not bring it back. */
export async function refuseDeleted(kind: RecordKind, recordId: string): Promise<void> {
  if (await deletedRecord(kind, recordId)) {
    throw new HttpError(410, "ข้อมูลนี้ถูกลบไปแล้ว", { code: "DELETED" });
  }
}

/** A repeated delete from an offline queue succeeds quietly. */
export async function wasDeletedBy(kind: RecordKind, recordId: string, farmerId: string): Promise<boolean> {
  const record = await deletedRecord(kind, recordId);
  return record?.farmerId === farmerId;
}
