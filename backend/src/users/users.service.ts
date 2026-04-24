import { ForbiddenException, Injectable } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { PrismaService } from "../prisma/prisma.service";
import { CreateKitchenUserDto } from "./dto/create-kitchen-user.dto";

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async createKitchenUser(dto: CreateKitchenUserDto, user: AuthenticatedUser) {
    this.assertRestaurantScope(dto.restaurantId, user);
    return this.prisma.user.upsert({
      where: { phone: this.normalizePhone(dto.phone) },
      update: { role: UserRole.KITCHEN, restaurantId: dto.restaurantId },
      create: {
        phone: this.normalizePhone(dto.phone),
        role: UserRole.KITCHEN,
        restaurantId: dto.restaurantId,
      },
      select: {
        id: true,
        phone: true,
        role: true,
        restaurantId: true,
        createdAt: true,
      },
    });
  }

  async listKitchenUsers(restaurantId: string, user: AuthenticatedUser) {
    this.assertRestaurantScope(restaurantId, user);
    return this.prisma.user.findMany({
      where: { restaurantId, role: UserRole.KITCHEN },
      select: {
        id: true,
        phone: true,
        role: true,
        restaurantId: true,
        createdAt: true,
      },
      orderBy: { createdAt: "desc" },
    });
  }

  private assertRestaurantScope(
    restaurantId: string,
    user: AuthenticatedUser,
  ): void {
    if (user.role === UserRole.SUPER_ADMIN) {
      return;
    }

    if (user.restaurantId !== restaurantId) {
      throw new ForbiddenException("Restaurant access denied.");
    }
  }

  private normalizePhone(phone: string): string {
    return phone.replace(/\s+/g, "");
  }
}
