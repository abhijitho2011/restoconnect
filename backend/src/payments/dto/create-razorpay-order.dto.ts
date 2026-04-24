import { IsInt, IsObject, IsOptional, IsString, Min } from "class-validator";

export class CreateRazorpayOrderDto {
  @IsInt()
  @Min(100)
  amountPaise!: number;

  @IsOptional()
  @IsString()
  currency?: string;

  @IsOptional()
  @IsString()
  receipt?: string;

  @IsOptional()
  @IsObject()
  notes?: Record<string, string>;
}
