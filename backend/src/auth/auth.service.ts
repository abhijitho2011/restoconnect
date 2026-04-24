import {
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { JwtService } from "@nestjs/jwt";
import { UserRole } from "@prisma/client";
import * as bcrypt from "bcryptjs";
import { PrismaService } from "../prisma/prisma.service";
import { SendOtpDto } from "./dto/send-otp.dto";
import { VerifyOtpDto } from "./dto/verify-otp.dto";
import { OtpService } from "./otp.service";

@Injectable()
export class AuthService {
  constructor(
    private readonly config: ConfigService,
    private readonly jwt: JwtService,
    private readonly otpService: OtpService,
    private readonly prisma: PrismaService,
  ) {}

  async sendOtp(
    dto: SendOtpDto,
  ): Promise<{ message: string; expiresAt: Date; devOtp?: string }> {
    const phone = this.normalizePhone(dto.phone);
    await this.ensureLoginAllowed(phone, dto.role);

    const otp = this.generateOtp();
    const otpHash = await bcrypt.hash(otp, 10);
    const ttlSeconds = this.config.get<number>("OTP_TTL_SECONDS", 300);
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    await this.prisma.otpCode.upsert({
      where: { phone },
      update: { otp: otpHash, expiresAt, attempts: 0 },
      create: { phone, otp: otpHash, expiresAt },
    });

    await this.otpService.send(phone, otp);
    const response: { message: string; expiresAt: Date; devOtp?: string } = {
      message: "OTP sent successfully.",
      expiresAt,
    };

    if (this.config.get<boolean>("OTP_DEV_MODE", false)) {
      response.devOtp = otp;
    }

    return response;
  }

  async verifyOtp(dto: VerifyOtpDto): Promise<{
    accessToken: string;
    user: {
      id: string;
      phone: string;
      role: UserRole;
      restaurantId: string | null;
    };
  }> {
    const phone = this.normalizePhone(dto.phone);
    const code = await this.prisma.otpCode.findUnique({ where: { phone } });

    if (!code || code.expiresAt.getTime() < Date.now()) {
      throw new UnauthorizedException("OTP has expired.");
    }

    if (code.attempts >= 5) {
      throw new UnauthorizedException("Too many OTP attempts.");
    }

    const isValid = await bcrypt.compare(dto.otp, code.otp);
    if (!isValid) {
      await this.prisma.otpCode.update({
        where: { phone },
        data: { attempts: { increment: 1 } },
      });
      throw new UnauthorizedException("Invalid OTP.");
    }

    const user = await this.resolveUserForLogin(phone, dto.role);
    await this.prisma.otpCode.delete({ where: { phone } });

    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      phone: user.phone,
      role: user.role,
      restaurantId: user.restaurantId,
    });

    return { accessToken, user };
  }

  private async ensureLoginAllowed(
    phone: string,
    role: UserRole,
  ): Promise<void> {
    const user = await this.prisma.user.findFirst({ where: { phone, role } });
    if (user) {
      return;
    }

    if (this.canBootstrapSuperAdmin(phone, role)) {
      return;
    }

    throw new ForbiddenException(
      "No active account found for this phone and role.",
    );
  }

  private async resolveUserForLogin(
    phone: string,
    role: UserRole,
  ): Promise<{
    id: string;
    phone: string;
    role: UserRole;
    restaurantId: string | null;
  }> {
    const user = await this.prisma.user.findFirst({
      where: { phone, role },
      select: { id: true, phone: true, role: true, restaurantId: true },
    });

    if (user) {
      return user;
    }

    if (this.canBootstrapSuperAdmin(phone, role)) {
      return this.prisma.user.create({
        data: { phone, role: UserRole.SUPER_ADMIN },
        select: { id: true, phone: true, role: true, restaurantId: true },
      });
    }

    throw new ForbiddenException("Account is not provisioned.");
  }

  private canBootstrapSuperAdmin(phone: string, role: UserRole): boolean {
    const bootstrapPhone = this.config.get<string>(
      "SUPER_ADMIN_BOOTSTRAP_PHONE",
    );
    return (
      role === UserRole.SUPER_ADMIN &&
      Boolean(bootstrapPhone) &&
      phone === bootstrapPhone
    );
  }

  private generateOtp(): string {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  private normalizePhone(phone: string): string {
    return phone.replace(/\s+/g, "");
  }
}
