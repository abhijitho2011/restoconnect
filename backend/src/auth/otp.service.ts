import { Injectable, Logger } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

@Injectable()
export class OtpService {
  private readonly logger = new Logger(OtpService.name);

  constructor(private readonly config: ConfigService) {}

  async send(phone: string, otp: string): Promise<void> {
    if (this.config.get<boolean>("OTP_DEV_MODE", false)) {
      this.logger.warn(`OTP for ${phone}: ${otp}`);
      return;
    }

    this.logger.log(
      `OTP generated for ${phone}. Configure SMS provider integration for production sends.`,
    );
  }
}
