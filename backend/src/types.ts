import type { AppRole } from "./access";

export type AuthUser = {
  id: string;
  keycloakId: string;
  username: string;
  role: AppRole;
  displayName: string;
};

declare global {
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}
