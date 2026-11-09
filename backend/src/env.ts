function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing ${name}. Copy backend/.env.example to backend/.env when the services exist.`);
  }
  return value;
}

const baseUrl = required("KEYCLOAK_BASE_URL").replace(/\/$/, "");
const realm = required("KEYCLOAK_REALM");

export const env = {
  port: Number(process.env.PORT ?? 3000),
  databaseUrl: required("DATABASE_URL"),
  keycloakBaseUrl: baseUrl,
  keycloakRealm: realm,
  keycloakIssuer: (process.env.KEYCLOAK_ISSUER?.trim() || `${baseUrl}/realms/${realm}`).replace(/\/$/, ""),
  keycloakClientId: required("KEYCLOAK_CLIENT_ID"),
};

if (!Number.isInteger(env.port) || env.port < 1 || env.port > 65535) {
  throw new Error("PORT must be a number from 1 to 65535");
}
