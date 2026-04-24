import {
  IsBoolean,
  IsNumber,
  IsOptional,
  IsString,
  IsUrl,
  Length,
  Min,
} from "class-validator";

export class UpdateMenuItemDto {
  @IsOptional()
  @IsString()
  @Length(2, 120)
  name?: string;

  @IsOptional()
  @IsNumber({ maxDecimalPlaces: 2 })
  @Min(0)
  price?: number;

  @IsOptional()
  @IsUrl({ require_tld: false })
  imageUrl?: string | null;

  @IsOptional()
  @IsUrl({ require_tld: false })
  modelGlbUrl?: string | null;

  @IsOptional()
  @IsUrl({ require_tld: false })
  modelUsdzUrl?: string | null;

  @IsOptional()
  @IsBoolean()
  isAvailable?: boolean;
}
