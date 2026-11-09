import { HttpError } from "./http";

export type AppRole = "FARMER" | "OFFICER";

export type Actor = {
  id: string;
  role: AppRole;
};

/** Keycloak realm roles used by this app. Any other role is ignored. */
export function roleFromRealmRoles(roles: readonly string[]): AppRole {
  const farmer = roles.includes("farmer");
  const officer = roles.includes("officer");
  if (farmer && officer) throw new HttpError(403, "บัญชีมีได้หนึ่ง role");
  if (farmer) return "FARMER";
  if (officer) return "OFFICER";
  throw new HttpError(403, "บัญชีไม่มี role ของแอป");
}

export function canReadFarmer(actor: Actor, farmerId: string, assignedFarmerIds: ReadonlySet<string>): boolean {
  if (actor.role === "FARMER") return actor.id === farmerId;
  return assignedFarmerIds.has(farmerId);
}

/** Officers can read. Only the farmer who owns the plot can change it. */
export function canWriteFarmer(actor: Actor, farmerId: string): boolean {
  return actor.role === "FARMER" && actor.id === farmerId;
}
