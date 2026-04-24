import { UserRole } from "@prisma/client";
import { IsEnum, IsPhoneNumber, IsString, Length } from "class-validator";

export class VerifyOtpDto {
  @IsPhoneNumber()
  phone!: string;

  @IsEnum(UserRole)
  role!: UserRole;

  @IsString()
  @Length(4, 8)
  otp!: string;
}
