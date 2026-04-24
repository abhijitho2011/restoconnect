import { Body, Controller, Get, Post, Query, UseGuards } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Roles } from "../common/decorators/roles.decorator";
import { JwtAuthGuard } from "../common/guards/jwt-auth.guard";
import { RolesGuard } from "../common/guards/roles.guard";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateKitchenUserDto } from "./dto/create-kitchen-user.dto";
import { UsersService } from "./users.service";

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("users")
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Post("kitchen")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  createKitchenUser(
    @Body() dto: CreateKitchenUserDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.usersService.createKitchenUser(dto, user);
  }

  @Get("kitchen")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  listKitchenUsers(
    @Query("restaurantId") restaurantId: string,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.usersService.listKitchenUsers(restaurantId, user);
  }
}
