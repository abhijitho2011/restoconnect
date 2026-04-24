import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { PrismaService } from "../prisma/prisma.service";
import { CreateRestaurantDto } from "./dto/create-restaurant.dto";
import { CreateSubscriptionPlanDto } from "./dto/create-subscription-plan.dto";
import { UpdateRestaurantStatusDto } from "./dto/update-restaurant-status.dto";

@Injectable()
export class RestaurantsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(dto: CreateRestaurantDto) {
    return this.prisma.$transaction(async (tx) => {
      const restaurant = await tx.restaurant.create({
        data: {
          name: dto.name,
          subscriptionPlan: dto.subscriptionPlan,
          gstNumber: dto.gstNumber,
        },
      });

      if (dto.ownerPhone) {
        await tx.user.upsert({
          where: { phone: this.normalizePhone(dto.ownerPhone) },
          update: {
            role: UserRole.RESTAURANT_OWNER,
            restaurantId: restaurant.id,
          },
          create: {
            phone: this.normalizePhone(dto.ownerPhone),
            role: UserRole.RESTAURANT_OWNER,
            restaurantId: restaurant.id,
          },
        });
      }

      return restaurant;
    });
  }

  async findAll(user: AuthenticatedUser) {
    if (user.role === UserRole.SUPER_ADMIN) {
      return this.prisma.restaurant.findMany({
        orderBy: { createdAt: "desc" },
        include: {
          _count: { select: { orders: true, tables: true, users: true } },
        },
      });
    }

    if (!user.restaurantId) {
      throw new ForbiddenException("User is not assigned to a restaurant.");
    }

    return this.prisma.restaurant.findMany({
      where: { id: user.restaurantId },
      include: {
        _count: { select: { orders: true, tables: true, users: true } },
      },
    });
  }

  async findOne(id: string, user: AuthenticatedUser) {
    this.assertRestaurantScope(id, user);
    const restaurant = await this.prisma.restaurant.findUnique({
      where: { id },
      include: { tables: true, users: true },
    });

    if (!restaurant) {
      throw new NotFoundException("Restaurant not found.");
    }

    return restaurant;
  }

  async updateStatus(id: string, dto: UpdateRestaurantStatusDto) {
    await this.ensureRestaurantExists(id);
    return this.prisma.restaurant.update({
      where: { id },
      data: { status: dto.status },
    });
  }

  async analytics(user: AuthenticatedUser) {
    const where =
      user.role === UserRole.SUPER_ADMIN
        ? {}
        : { restaurantId: user.restaurantId ?? "" };
    const [orders, restaurants, revenue] = await Promise.all([
      this.prisma.order.count({ where }),
      user.role === UserRole.SUPER_ADMIN
        ? this.prisma.restaurant.count()
        : Promise.resolve(1),
      this.prisma.order.aggregate({ where, _sum: { totalAmount: true } }),
    ]);

    return {
      orders,
      restaurants,
      revenue: Number(revenue._sum.totalAmount ?? 0),
    };
  }

  async createSubscriptionPlan(dto: CreateSubscriptionPlanDto) {
    return this.prisma.subscriptionPlan.upsert({
      where: { code: dto.code.toUpperCase() },
      update: {
        name: dto.name,
        monthlyPricePaise: dto.monthlyPricePaise,
        features: dto.features,
        isActive: dto.isActive ?? true,
      },
      create: {
        code: dto.code.toUpperCase(),
        name: dto.name,
        monthlyPricePaise: dto.monthlyPricePaise,
        features: dto.features,
        isActive: dto.isActive ?? true,
      },
    });
  }

  async listSubscriptionPlans() {
    return this.prisma.subscriptionPlan.findMany({
      orderBy: { monthlyPricePaise: "asc" },
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

  private async ensureRestaurantExists(id: string): Promise<void> {
    const restaurant = await this.prisma.restaurant.findUnique({
      where: { id },
      select: { id: true },
    });
    if (!restaurant) {
      throw new NotFoundException("Restaurant not found.");
    }
  }

  private normalizePhone(phone: string): string {
    return phone.replace(/\s+/g, "");
  }
}
