import { IsPhoneNumber, IsUUID } from "class-validator";

export class CreateKitchenUserDto {
  @IsUUID()
  restaurantId!: string;

  @IsPhoneNumber()
  phone!: string;
}
