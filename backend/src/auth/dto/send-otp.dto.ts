import { UserRole } from "@prisma/client";
import { IsEnum, IsPhoneNumber } from "class-validator";

export class SendOtpDto {
  @IsPhoneNumber()
  phone!: string;

  @IsEnum(UserRole)
  role!: UserRole;
}
