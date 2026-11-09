import type { NextFunction, Request, Response } from "express";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";
import { roleFromRealmRoles } from "./access";
import { env } from "./env";
import { HttpError } from "./http";
import { prisma } from "./prisma";
import type { AuthUser } from "./types";

const jwks = createRemoteJWKSet(
  new URL(`/realms/${env.keycloakRealm}/protocol/openid-connect/certs`, `${env.keycloakBaseUrl}/`),
);

function textClaim(payload: JWTPayload, key: string): string | undefined {
  const value = payload[key];
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed === "" ? undefined : trimmed;
}

function realmRoles(payload: JWTPayload): string[] {
  const access = payload.realm_access;
  if (!access || typeof access !== "object" || !("roles" in access) || !Array.isArray(access.roles)) {
    return [];
  }
  return access.roles.filter((role): role is string => typeof role === "string");
}

export function currentUser(req: Request): AuthUser {
  if (!req.user) throw new HttpError(401, "ต้องเข้าสู่ระบบ");
  return req.user;
}

export function requireAuth(req: Request, _res: Response, next: NextFunction) {
  authenticate(req).then(() => next(), next);
}

export async function authenticate(req: Request): Promise<void> {
  const header = req.header("authorization");
  if (!header?.startsWith("Bearer ")) throw new HttpError(401, "ต้องเข้าสู่ระบบ");
  const token = header.slice("Bearer ".length).trim();
  if (!token) throw new HttpError(401, "ต้องเข้าสู่ระบบ");

  let payload: JWTPayload;
  try {
    const verified = await jwtVerify(token, jwks, { issuer: env.keycloakIssuer });
    payload = verified.payload;
  } catch {
    throw new HttpError(401, "โทเคนไม่ถูกต้องหรือหมดอายุ");
  }

  if (payload.azp !== env.keycloakClientId) throw new HttpError(401, "โทเคนไม่ใช่ของแอปนี้");
  if (typeof payload.sub !== "string" || payload.sub === "") throw new HttpError(401, "โทเคนไม่มีผู้ใช้");

  const role = roleFromRealmRoles(realmRoles(payload));
  const username = textClaim(payload, "preferred_username") ?? payload.sub;
  const displayName = textClaim(payload, "name") ?? username;

  const user = await prisma.user.upsert({
    where: { keycloakId: payload.sub },
    create: { keycloakId: payload.sub, username, role, displayName },
    update: { username, role, displayName },
  });

  req.user = {
    id: user.id,
    keycloakId: user.keycloakId,
    username: user.username,
    role: user.role,
    displayName: user.displayName,
  };
}
