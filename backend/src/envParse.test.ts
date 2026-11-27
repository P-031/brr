import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { issuerAliases, parseCorsOrigins } from "./envParse";

describe("parseCorsOrigins", () => {
  it("returns an empty list when unset or blank", () => {
    assert.deepEqual(parseCorsOrigins(undefined), []);
    assert.deepEqual(parseCorsOrigins(""), []);
    assert.deepEqual(parseCorsOrigins("  ,  ,"), []);
  });

  it("keeps trimmed origins", () => {
    assert.deepEqual(parseCorsOrigins("https://a.example, https://b.example"), [
      "https://a.example",
      "https://b.example",
    ]);
  });
});

describe("issuerAliases", () => {
  it("keeps only the configured issuer when loopback aliases are off", () => {
    assert.deepEqual(issuerAliases("https://auth.example.com/realms/brr", false), [
      "https://auth.example.com/realms/brr",
    ]);
  });

  it("adds loopback hosts in development", () => {
    assert.deepEqual(issuerAliases("http://auth.example:8080/realms/brr", true), [
      "http://auth.example:8080/realms/brr",
      "http://127.0.0.1:8080/realms/brr",
      "http://localhost:8080/realms/brr",
      "http://10.0.2.2:8080/realms/brr",
    ]);
  });
});
