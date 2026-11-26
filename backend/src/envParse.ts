export function parseCorsOrigins(value: string | undefined): string[] {
  return value?.split(",").map((s) => s.trim()).filter(Boolean) ?? [];
}

/** In development Keycloak may stamp the issuer with localhost, 127.0.0.1, or the Android emulator host. */
export function issuerAliases(value: string, allowLoopback = process.env.NODE_ENV !== "production"): string[] {
  if (!allowLoopback) return [value];
  const match = value.match(/^(https?:\/\/)[^/:]+(:\d+)?(\/.*)$/);
  if (!match) return [value];
  const [, scheme, port = "", path] = match;
  const aliases = ["127.0.0.1", "localhost", "10.0.2.2"].map((host) => `${scheme}${host}${port}${path}`);
  return [...new Set([value, ...aliases])];
}
