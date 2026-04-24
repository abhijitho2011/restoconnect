import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { UserRole } from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { PrismaService } from "../prisma/prisma.service";
import { CreateTableDto } from "./dto/create-table.dto";

@Injectable()
export class TablesService {
  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  async create(dto: CreateTableDto, user: AuthenticatedUser) {
    this.assertRestaurantScope(dto.restaurantId, user);
    await this.ensureRestaurantExists(dto.restaurantId);

    const table = await this.prisma.restaurantTable.create({
      data: {
        restaurantId: dto.restaurantId,
        tableNumber: dto.tableNumber,
        qrCodeUrl: "",
      },
    });

    const qrCodeUrl = this.buildQrCodeUrl(dto.restaurantId, table.id);
    return this.prisma.restaurantTable.update({
      where: { id: table.id },
      data: { qrCodeUrl },
    });
  }

  async findAll(restaurantId: string, user: AuthenticatedUser) {
    this.assertRestaurantScope(restaurantId, user);
    return this.prisma.restaurantTable.findMany({
      where: { restaurantId },
      orderBy: { tableNumber: "asc" },
    });
  }

  private buildQrCodeUrl(restaurantId: string, tableId: string): string {
    const baseUrl = this.config
      .get<string>("PUBLIC_CUSTOMER_APP_URL", "")
      .replace(/\/+$/, "");
    return `${baseUrl}/r/${restaurantId}/t/${tableId}`;
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
}
