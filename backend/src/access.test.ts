import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { canReadFarmer, canWriteFarmer, roleFromRealmRoles } from "./access";
import { HttpError } from "./http";

const farmer = { id: "farmer-1", role: "FARMER" as const };
const officer = { id: "officer-1", role: "OFFICER" as const };
const assigned = new Set(["farmer-1"]);

describe("roles", () => {
  it("keeps a single app role", () => {
    assert.equal(roleFromRealmRoles(["farmer", "offline_access"]), "FARMER");
    assert.equal(roleFromRealmRoles(["officer"]), "OFFICER");
  });

  it("rejects an account with both roles or neither", () => {
    assert.throws(() => roleFromRealmRoles(["farmer", "officer"]), (error: unknown) => {
      return error instanceof HttpError && error.status === 403;
    });
    assert.throws(() => roleFromRealmRoles(["uma_authorization"]), (error: unknown) => {
      return error instanceof HttpError && error.status === 403;
    });
  });
});

describe("plot access", () => {
  it("lets a farmer read and write only their own plots", () => {
    assert.equal(canReadFarmer(farmer, "farmer-1", assigned), true);
    assert.equal(canReadFarmer(farmer, "farmer-2", assigned), false);
    assert.equal(canWriteFarmer(farmer, "farmer-1"), true);
    assert.equal(canWriteFarmer(farmer, "farmer-2"), false);
  });

  it("lets an officer read assigned farmers and write nothing", () => {
    assert.equal(canReadFarmer(officer, "farmer-1", assigned), true);
    assert.equal(canReadFarmer(officer, "farmer-2", assigned), false);
    assert.equal(canWriteFarmer(officer, "farmer-1"), false);
  });
});
