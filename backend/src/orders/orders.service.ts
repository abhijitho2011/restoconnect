import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import {
  OrderStatus,
  Prisma,
  RestaurantStatus,
  UserRole,
} from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { PrismaService } from "../prisma/prisma.service";
import { CreateOrderDto } from "./dto/create-order.dto";
import { ListOrdersDto } from "./dto/list-orders.dto";
import { UpdateOrderStatusDto } from "./dto/update-order-status.dto";
import { OrdersGateway } from "./orders.gateway";

@Injectable()
export class OrdersService {
  constructor(
    private readonly ordersGateway: OrdersGateway,
    private readonly prisma: PrismaService,
  ) {}

  async create(dto: CreateOrderDto) {
    const order = await this.prisma.$transaction(async (tx) => {
      const restaurant = await tx.restaurant.findUnique({
        where: { id: dto.restaurantId },
      });
      if (!restaurant || restaurant.status !== RestaurantStatus.APPROVED) {
        throw new BadRequestException("Restaurant is not accepting orders.");
      }

      const table = await tx.restaurantTable.findFirst({
        where: { id: dto.tableId, restaurantId: dto.restaurantId },
      });
      if (!table) {
        throw new BadRequestException(
          "Table does not belong to this restaurant.",
        );
      }

      const itemIds = [...new Set(dto.items.map((item) => item.itemId))];
      const menuItems = await tx.menuItem.findMany({
        where: {
          id: { in: itemIds },
          isAvailable: true,
          category: { restaurantId: dto.restaurantId },
        },
      });

      if (menuItems.length !== itemIds.length) {
        throw new BadRequestException(
          "One or more menu items are unavailable.",
        );
      }

      const menuById = new Map(menuItems.map((item) => [item.id, item]));
      const lines = dto.items.map((line) => {
        const menuItem = menuById.get(line.itemId);
        if (!menuItem) {
          throw new BadRequestException("Menu item is unavailable.");
        }

        const unitPrice = Number(menuItem.price);
        const lineTotal = this.roundMoney(unitPrice * line.quantity);
        return {
          itemId: line.itemId,
          quantity: line.quantity,
          unitPrice,
          lineTotal,
        };
      });

      const subtotalAmount = this.roundMoney(
        lines.reduce((total, line) => total + line.lineTotal, 0),
      );
      const gstAmount = this.roundMoney(
        (subtotalAmount * Number(restaurant.gstPercent)) / 100,
      );
      const serviceChargeAmount = this.roundMoney(
        (subtotalAmount * Number(restaurant.serviceChargePercent)) / 100,
      );
      const totalAmount = this.roundMoney(
        subtotalAmount + gstAmount + serviceChargeAmount,
      );

      return tx.order.create({
        data: {
          restaurantId: dto.restaurantId,
          tableId: dto.tableId,
          subtotalAmount,
          gstAmount,
          serviceChargeAmount,
          totalAmount,
          items: {
            create: lines.map((line) => ({
              itemId: line.itemId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
              lineTotal: line.lineTotal,
            })),
          },
        },
        include: this.orderInclude(),
      });
    });

    this.ordersGateway.emitOrderCreated(order);
    return order;
  }

  async findAll(query: ListOrdersDto, user: AuthenticatedUser) {
    const restaurantId = this.resolveRestaurantId(query.restaurantId, user);
    const where: Prisma.OrderWhereInput = {
      restaurantId,
      tableId: query.tableId,
      status: query.status,
    };

    return this.prisma.order.findMany({
      where,
      include: this.orderInclude(),
      orderBy: { createdAt: "desc" },
      take: 100,
    });
  }

  async findForTable(restaurantId: string, tableId: string) {
    return this.prisma.order.findMany({
      where: { restaurantId, tableId },
      include: this.orderInclude(),
      orderBy: { createdAt: "desc" },
      take: 20,
    });
  }

  async updateStatus(
    id: string,
    dto: UpdateOrderStatusDto,
    user: AuthenticatedUser,
  ) {
    const existing = await this.prisma.order.findUnique({
      where: { id },
      select: { id: true, restaurantId: true },
    });

    if (!existing) {
      throw new NotFoundException("Order not found.");
    }

    this.assertRestaurantScope(existing.restaurantId, user);
    this.assertStatusAllowed(dto.status);

    const order = await this.prisma.order.update({
      where: { id },
      data: { status: dto.status },
      include: this.orderInclude(),
    });

    this.ordersGateway.emitOrderUpdated(order);
    return order;
  }

  private resolveRestaurantId(
    restaurantId: string | undefined,
    user: AuthenticatedUser,
  ): string | undefined {
    if (user.role === UserRole.SUPER_ADMIN) {
      return restaurantId;
    }

    if (!user.restaurantId) {
      throw new ForbiddenException("User is not assigned to a restaurant.");
    }

    if (restaurantId && restaurantId !== user.restaurantId) {
      throw new ForbiddenException("Restaurant access denied.");
    }

    return user.restaurantId;
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

  private assertStatusAllowed(status: OrderStatus): void {
    const allowed = [
      OrderStatus.PENDING,
      OrderStatus.PREPARING,
      OrderStatus.READY,
      OrderStatus.SERVED,
      OrderStatus.CANCELLED,
    ];
    if (!allowed.includes(status)) {
      throw new BadRequestException("Unsupported order status.");
    }
  }

  private roundMoney(amount: number): number {
    return Math.round((amount + Number.EPSILON) * 100) / 100;
  }

  private orderInclude() {
    return {
      table: true,
      items: { include: { item: true } },
    } satisfies Prisma.OrderInclude;
  }
}
