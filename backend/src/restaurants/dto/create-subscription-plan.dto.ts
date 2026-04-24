import {
  IsArray,
  IsBoolean,
  IsInt,
  IsOptional,
  IsString,
  Length,
  Min,
} from "class-validator";

export class CreateSubscriptionPlanDto {
  @IsString()
  @Length(2, 40)
  code!: string;

  @IsString()
  @Length(2, 80)
  name!: string;

  @IsInt()
  @Min(0)
  monthlyPricePaise!: number;

  @IsArray()
  @IsString({ each: true })
  features!: string[];

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
