import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  UseGuards,
} from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Roles } from "../common/decorators/roles.decorator";
import { JwtAuthGuard } from "../common/guards/jwt-auth.guard";
import { RolesGuard } from "../common/guards/roles.guard";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateRestaurantDto } from "./dto/create-restaurant.dto";
import { CreateSubscriptionPlanDto } from "./dto/create-subscription-plan.dto";
import { UpdateRestaurantStatusDto } from "./dto/update-restaurant-status.dto";
import { RestaurantsService } from "./restaurants.service";

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("restaurants")
export class RestaurantsController {
  constructor(private readonly restaurantsService: RestaurantsService) {}

  @Post()
  @Roles(UserRole.SUPER_ADMIN)
  create(@Body() dto: CreateRestaurantDto) {
    return this.restaurantsService.create(dto);
  }

  @Get()
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  findAll(@CurrentUser() user: AuthenticatedUser) {
    return this.restaurantsService.findAll(user);
  }

  @Get("analytics")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  analytics(@CurrentUser() user: AuthenticatedUser) {
    return this.restaurantsService.analytics(user);
  }

  @Post("subscription-plans")
  @Roles(UserRole.SUPER_ADMIN)
  createSubscriptionPlan(@Body() dto: CreateSubscriptionPlanDto) {
    return this.restaurantsService.createSubscriptionPlan(dto);
  }

  @Get("subscription-plans")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  listSubscriptionPlans() {
    return this.restaurantsService.listSubscriptionPlans();
  }

  @Get(":id")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  findOne(@Param("id") id: string, @CurrentUser() user: AuthenticatedUser) {
    return this.restaurantsService.findOne(id, user);
  }

  @Patch(":id/status")
  @Roles(UserRole.SUPER_ADMIN)
  updateStatus(
    @Param("id") id: string,
    @Body() dto: UpdateRestaurantStatusDto,
  ) {
    return this.restaurantsService.updateStatus(id, dto);
  }
}
