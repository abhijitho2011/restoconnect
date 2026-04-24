import { Body, Controller, Post, UseGuards } from "@nestjs/common";
import { UserRole } from "@prisma/client";
import { CurrentUser } from "../common/decorators/current-user.decorator";
import { Roles } from "../common/decorators/roles.decorator";
import { JwtAuthGuard } from "../common/guards/jwt-auth.guard";
import { RolesGuard } from "../common/guards/roles.guard";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateSignedUploadDto } from "./dto/create-signed-upload.dto";
import { UploadsService } from "./uploads.service";

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller("uploads")
export class UploadsController {
  constructor(private readonly uploadsService: UploadsService) {}

  @Post("signed-url")
  @Roles(UserRole.SUPER_ADMIN, UserRole.RESTAURANT_OWNER)
  createSignedUrl(
    @Body() dto: CreateSignedUploadDto,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    return this.uploadsService.createSignedUrl(dto, user);
  }
}
