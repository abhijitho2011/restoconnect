import { Body, Controller, Get, Post, Query, UseGuards } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Roles } from "../common/decorators/roles.decorator";
import { JwtAuthGuard } from "../common/guards/jwt-auth.guard";
import { RolesGuard } from "../common/guards/roles.guard";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateTableDto } from "./dto/create-table.dto";
import { TablesService } from "./tables.service";

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("tables")
export class TablesController {
  constructor(private readonly tablesService: TablesService) {}

  @Post()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  create(@Body() dto: CreateTableDto, @CurrentUser() user: AuthenticatedUser) {
    return this.tablesService.create(dto, user);
  }

  @Get()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER, UserRole.KITCHEN)
  findAll(
    @Query("restaurantId") restaurantId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.tablesService.findAll(restaurantId, user);
  }
}
