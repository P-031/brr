import { issuerAliases, parseCorsOrigins } from "./envParse";

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing ${name}. Copy backend/.env.example to backend/.env when the services exist.`);
  }
  return value;
}

const baseUrl = required("KEYCLOAK_BASE_URL").replace(/\/$/, "");
const realm = required("KEYCLOAK_REALM");
const issuer = (process.env.KEYCLOAK_ISSUER?.trim() || `${baseUrl}/realms/${realm}`).replace(/\/$/, "");

export const env = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: required("DATABASE_URL"),
  keycloakBaseUrl: baseUrl,
  keycloakRealm: realm,
  keycloakIssuer: issuer,
  keycloakIssuers: issuerAliases(
    issuer,
    process.env.NODE_ENV !== "production" || process.env.ALLOW_ISSUER_ALIASES === "1",
  ),
  keycloakClientId: required("KEYCLOAK_CLIENT_ID"),
  corsOrigins: parseCorsOrigins(process.env.CORS_ORIGINS),
};

if (!Number.isInteger(env.port) || env.port < 1 || env.port > 65535) {
  throw new Error("PORT must be a number from 1 to 65535");
}

if (process.env.NODE_ENV === "production" && env.corsOrigins.length === 0) {
  throw new Error("CORS_ORIGINS must be set in production to a comma-separated list of allowed origins");
}
