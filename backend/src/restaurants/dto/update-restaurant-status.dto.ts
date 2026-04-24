import { RestaurantStatus } from "@prisma/client";
import { IsEnum } from "class-validator";

export class UpdateRestaurantStatusDto {
  @IsEnum(RestaurantStatus)
  status!: RestaurantStatus;
}
