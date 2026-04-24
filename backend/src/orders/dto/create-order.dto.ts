import { Type } from "class-transformer";
import {
  ArrayMinSize,
  IsInt,
  IsUUID,
  Min,
  ValidateNested,
} from "class-validator";

export class CreateOrderItemDto {
  @IsUUID()
  itemId!: string;

  @IsInt()
  @Min(1)
  quantity!: number;
}

export class CreateOrderDto {
  @IsUUID()
  restaurantId!: string;

  @IsUUID()
  tableId!: string;

  @ArrayMinSize(1)
  @ValidateNested({ each: true })
  @Type(() => CreateOrderItemDto)
  items!: CreateOrderItemDto[];
}
