import { IsInt, IsOptional, IsString, Length, Min } from "class-validator";

export class UpdateCategoryDto {
  @IsOptional()
  @IsString()
  @Length(2, 80)
  name?: string;

  @IsOptional()
  @IsInt()
  @Min(0)
  sortOrder?: number;
}
