import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Roles } from "../common/decorators/roles.decorator";
import { JwtAuthGuard } from "../common/guards/jwt-auth.guard";
import { RolesGuard } from "../common/guards/roles.guard";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateCategoryDto } from "./dto/create-category.dto";
import { CreateMenuItemDto } from "./dto/create-menu-item.dto";
import { UpdateCategoryDto } from "./dto/update-category.dto";
import { UpdateMenuItemDto } from "./dto/update-menu-item.dto";
import { MenuService } from "./menu.service";

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("menu/categories")
export class MenuCategoriesController {
  constructor(private readonly menuService: MenuService) {}

  @Post()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  create(
    @Body() dto: CreateCategoryDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.createCategory(dto, user);
  }

  @Get()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER, UserRole.KITCHEN)
  list(
    @Query("restaurantId") restaurantId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.listCategories(restaurantId, user);
  }

  @Patch(":id")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  update(
    @Param("id") id: string,
    @Body() dto: UpdateCategoryDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.updateCategory(id, dto, user);
  }

  @Delete(":id")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  delete(@Param("id") id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.menuService.deleteCategory(id, user);
  }
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("menu/items")
export class MenuItemsController {
  constructor(private readonly menuService: MenuService) {}

  @Post()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  create(
    @Body() dto: CreateMenuItemDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.createItem(dto, user);
  }

  @Get()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER, UserRole.KITCHEN)
  list(
    @Query("restaurantId") restaurantId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.listItems(restaurantId, user);
  }

  @Patch(":id")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  update(
    @Param("id") id: string,
    @Body() dto: UpdateMenuItemDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.menuService.updateItem(id, dto, user);
  }

  @Delete(":id")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  delete(@Param("id") id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.menuService.deleteItem(id, user);
  }
}

@Controller("menu/public")
export class PublicMenuController {
  constructor(private readonly menuService: MenuService) {}

  @Get(":restaurantId")
  publicMenu(@Param("restaurantId") restaurantId: string) {
    return this.menuService.publicMenu(restaurantId);
  }
}
