import { OrderStatus } from "@prisma/client";
import { IsEnum, IsOptional, IsUUID } from "class-validator";

export class ListOrdersDto {
  @IsOptional()
  @IsUUID()
  restaurantId?: string;

  @IsOptional()
  @IsUUID()
  tableId?: string;

  @IsOptional()
  @IsEnum(OrderStatus)
  status?: OrderStatus;
}
