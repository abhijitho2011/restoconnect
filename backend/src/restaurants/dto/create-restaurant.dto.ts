import {
  IsOptional,
  IsPhoneNumber,
  IsString,
  Length,
  Matches,
} from "class-validator";

export class CreateRestaurantDto {
  @IsString()
  @Length(2, 120)
  name!: string;

  @IsOptional()
  @IsString()
  @Length(2, 40)
  subscriptionPlan?: string;

  @IsOptional()
  @IsPhoneNumber()
  ownerPhone?: string;

  @IsOptional()
  @IsString()
  @Matches(/^[0-9A-Z-]{5,20}$/)
  gstNumber?: string;
}
