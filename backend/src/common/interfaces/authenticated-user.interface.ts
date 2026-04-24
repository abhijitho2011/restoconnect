import { UserRole } from "@prisma/client";

export interface AuthenticatedUser {
  sub: string;
  phone: string;
  role: UserRole;
  restaurantId: string | null;
}
