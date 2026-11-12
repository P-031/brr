import { Router } from "express";
import { z } from "zod";
import { env } from "../env";
import { HttpError, route } from "../http";

export const sessionRouter = Router();

const passwordBody = z.object({
  username: z.string().trim().min(1).max(200),
  password: z.string().min(1).max(200),
});

const refreshBody = z.object({
  refreshToken: z.string().min(1),
});

/** Browser pages cannot POST to Keycloak's port. The API calls it instead. */
async function keycloakToken(body: URLSearchParams): Promise<{ status: number; json: unknown }> {
  let response: Response;
  try {
    response = await fetch(`${env.keycloakIssuer}/protocol/openid-connect/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body,
    });
  } catch {
    throw new HttpError(503, "ติดต่อระบบเข้าสู่ระบบไม่ได้");
  }
  const json = await response.json().catch(() => ({ error: "invalid_response" }));
  return { status: response.status, json };
}

sessionRouter.post(
  "/api/v1/auth/token",
  route(async (req, res) => {
    const { username, password } = passwordBody.parse(req.body);
    const result = await keycloakToken(
      new URLSearchParams({
        grant_type: "password",
        client_id: env.keycloakClientId,
        username,
        password,
        scope: "openid profile email",
      }),
    );
    res.status(result.status).json(result.json);
  }),
);

sessionRouter.post(
  "/api/v1/auth/refresh",
  route(async (req, res) => {
    const { refreshToken } = refreshBody.parse(req.body);
    const result = await keycloakToken(
      new URLSearchParams({
        grant_type: "refresh_token",
        client_id: env.keycloakClientId,
        refresh_token: refreshToken,
      }),
    );
    res.status(result.status).json(result.json);
  }),
);
