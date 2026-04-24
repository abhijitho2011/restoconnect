import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  Length,
  Min,
} from "class-validator";

export class CreateMenuItemDto {
  @IsUUID()
  categoryId!: string;

  @IsString()
  @Length(2, 120)
  name!: string;

  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price!: number;

  @IsOptional()
  @IsUrl({ require_tld: false })
  imageUrl?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  modelGlbUrl?: string;

  @IsOptional()
  @IsUrl({ require_tld: false })
  modelUsdzUrl?: string;

  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;
}
