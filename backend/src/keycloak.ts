import { env } from "./env";
import { HttpError } from "./http";
import { cacheGet, cacheSet } from "./redis";

// Admin REST calls for user-level operations (password reset). The
// user's current password is verified via the public client's direct
// grant before touching the Admin API.

let adminToken: { value: string; expiresAt: number } | undefined;
const ADMIN_TOKEN_KEY = "kc:admin_token";

function tokenEndpoint(realm: string): string {
  return `${env.keycloakBaseUrl}/realms/${realm}/protocol/openid-connect/token`;
}

async function postToken(realm: string, params: Record<string, string>): Promise<Response> {
  return fetch(tokenEndpoint(realm), {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params),
  });
}

/// Throws 400 when the supplied credentials are rejected — used to
/// verify the old password before allowing a change.
export async function verifyUserPassword(username: string, password: string): Promise<void> {
  const res = await postToken(env.keycloakRealm, {
    grant_type: "password",
    client_id: env.keycloakClientId,
    username,
    password,
  });
  if (res.ok) return;
  const body = (await res.json().catch(() => ({}))) as { error?: string };
  if (res.status === 400 && body.error === "invalid_grant") {
    throw new HttpError(400, "รหัสผ่านเดิมไม่ถูกต้อง");
  }
  throw new HttpError(502, "ตรวจสอบรหัสผ่านกับ Keycloak ไม่ได้");
}

async function getAdminToken(): Promise<string> {
  // Redis first so multiple API instances share one token; the
  // in-memory copy keeps things working when Redis is down.
  const cached = await cacheGet(ADMIN_TOKEN_KEY);
  if (typeof cached === "string") return cached;
  if (adminToken && Date.now() < adminToken.expiresAt) return adminToken.value;
  const res = await postToken("master", {
    grant_type: "password",
    client_id: "admin-cli",
    username: env.keycloakAdminUsername,
    password: env.keycloakAdminPassword,
  });
  if (!res.ok) throw new HttpError(502, "เชื่อมต่อ Keycloak admin ไม่ได้");
  const data = (await res.json()) as { access_token: string; expires_in: number };
  adminToken = { value: data.access_token, expiresAt: Date.now() + (data.expires_in - 30) * 1000 };
  await cacheSet(ADMIN_TOKEN_KEY, data.access_token, data.expires_in - 30);
  return adminToken.value;
}

/// Resets the user's Keycloak password via the Admin REST API.
export async function resetUserPassword(keycloakId: string, newPassword: string): Promise<void> {
  const token = await getAdminToken();
  const res = await fetch(
    `${env.keycloakBaseUrl}/admin/realms/${env.keycloakRealm}/users/${keycloakId}/reset-password`,
    {
      method: "PUT",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({ type: "password", value: newPassword, temporary: false }),
    },
  );
  if (res.status === 404) throw new HttpError(404, "ไม่พบบัญชีใน Keycloak");
  if (!res.ok) throw new HttpError(502, "เปลี่ยนรหัสผ่านบน Keycloak ไม่สำเร็จ");
}
