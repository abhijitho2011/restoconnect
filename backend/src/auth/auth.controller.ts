import { Body, Controller, Post } from "@nestjs/common";
import { AuthService } from "./auth.service";
import { SendOtpDto } from "./dto/send-otp.dto";
import { VerifyOtpDto } from "./dto/verify-otp.dto";

@Controller("auth")
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post("send-otp")
  sendOtp(
    @Body() dto: SendOtpDto,
  ): Promise<{ message: string; expiresAt: Date; devOtp?: string }> {
    return this.authService.sendOtp(dto);
  }

  @Post("verify-otp")
  verifyOtp(@Body() dto: VerifyOtpDto): ReturnType<AuthService["verifyOtp"]> {
    return this.authService.verifyOtp(dto);
  }
}
