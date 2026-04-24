import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { PrismaService } from "../prisma/prisma.service";
import { CreateCategoryDto } from "./dto/create-category.dto";
import { CreateMenuItemDto } from "./dto/create-menu-item.dto";
import { UpdateCategoryDto } from "./dto/update-category.dto";
import { UpdateMenuItemDto } from "./dto/update-menu-item.dto";

@Injectable()
export class MenuService {
  constructor(private readonly prisma: PrismaService) {}

  async createCategory(dto: CreateCategoryDto, user: AuthenticatedUser) {
    this.assertRestaurantScope(dto.restaurantId, user);
    return this.prisma.menuCategory.create({
      data: {
        restaurantId: dto.restaurantId,
        name: dto.name,
        sortOrder: dto.sortOrder ?? 0,
      },
    });
  }

  async listCategories(restaurantId: string, user: AuthenticatedUser) {
    this.assertRestaurantScope(restaurantId, user);
    return this.prisma.menuCategory.findMany({
      where: { restaurantId },
      include: { items: { orderBy: { createdAt: "desc" } } },
      orderBy: [{ sortOrder: "asc" }, { name: "asc" }],
    });
  }

  async updateCategory(
    id: string,
    dto: UpdateCategoryDto,
    user: AuthenticatedUser,
  ) {
    const category = await this.getCategoryOrThrow(id);
    this.assertRestaurantScope(category.restaurantId, user);
    return this.prisma.menuCategory.update({ where: { id }, data: dto });
  }

  async deleteCategory(id: string, user: AuthenticatedUser) {
    const category = await this.getCategoryOrThrow(id);
    this.assertRestaurantScope(category.restaurantId, user);
    return this.prisma.menuCategory.delete({ where: { id } });
  }

  async createItem(dto: CreateMenuItemDto, user: AuthenticatedUser) {
    const category = await this.getCategoryOrThrow(dto.categoryId);
    this.assertRestaurantScope(category.restaurantId, user);
    return this.prisma.menuItem.create({
      data: {
        categoryId: dto.categoryId,
        name: dto.name,
        price: dto.price,
        imageUrl: dto.imageUrl,
        modelGlbUrl: dto.modelGlbUrl,
        modelUsdzUrl: dto.modelUsdzUrl,
        isAvailable: dto.isAvailable ?? true,
      },
    });
  }

  async listItems(restaurantId: string, user: AuthenticatedUser) {
    this.assertRestaurantScope(restaurantId, user);
    return this.prisma.menuItem.findMany({
      where: { category: { restaurantId } },
      include: { category: true },
      orderBy: { createdAt: "desc" },
    });
  }

  async updateItem(
    id: string,
    dto: UpdateMenuItemDto,
    user: AuthenticatedUser,
  ) {
    const item = await this.getItemOrThrow(id);
    this.assertRestaurantScope(item.category.restaurantId, user);
    return this.prisma.menuItem.update({ where: { id }, data: dto });
  }

  async deleteItem(id: string, user: AuthenticatedUser) {
    const item = await this.getItemOrThrow(id);
    this.assertRestaurantScope(item.category.restaurantId, user);
    return this.prisma.menuItem.delete({ where: { id } });
  }

  async publicMenu(restaurantId: string) {
    return this.prisma.menuCategory.findMany({
      where: {
        restaurantId,
        restaurant: { status: "APPROVED" },
      },
      include: {
        items: {
          where: { isAvailable: true },
          orderBy: { name: "asc" },
        },
      },
      orderBy: [{ sortOrder: "asc" }, { name: "asc" }],
    });
  }

  private async getCategoryOrThrow(id: string) {
    const category = await this.prisma.menuCategory.findUnique({
      where: { id },
    });
    if (!category) {
      throw new NotFoundException("Menu category not found.");
    }
    return category;
  }

  private async getItemOrThrow(id: string) {
    const item = await this.prisma.menuItem.findUnique({
      where: { id },
      include: { category: true },
    });
    if (!item) {
      throw new NotFoundException("Menu item not found.");
    }
    return item;
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
}
