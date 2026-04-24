import { IsString, IsUUID, Length } from "class-validator";

export class CreateTableDto {
  @IsUUID()
  restaurantId!: string;

  @IsString()
  @Length(1, 20)
  tableNumber!: string;
}
