import {
  ForbiddenException,
  Injectable,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { randomUUID } from "crypto";
import { UserRole } from "@prisma/client";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";
import { CreateSignedUploadDto } from "./dto/create-signed-upload.dto";

@Injectable()
export class UploadsService {
  private readonly s3: S3Client;

  constructor(private readonly config: ConfigService) {
    this.s3 = new S3Client({
      region: this.config.get<string>("AWS_REGION", "ap-south-1"),
    });
  }

  async createSignedUrl(dto: CreateSignedUploadDto, user: AuthenticatedUser) {
    this.assertRestaurantScope(dto.restaurantId, user);

    const bucket = this.config.get<string>("AWS_S3_BUCKET");
    if (!bucket) {
      throw new ServiceUnavailableException("S3 bucket is not configured.");
    }

    const safeName = dto.fileName.replace(/[^a-zA-Z0-9._-]/g, "-");
    const keyParts = [
      dto.folder,
      dto.restaurantId,
      dto.entityId,
      `${randomUUID()}-${safeName}`,
    ].filter(Boolean);
    const key = keyParts.join("/");

    const command = new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      ContentType: dto.contentType,
    });

    const expiresIn = this.config.get<number>(
      "SIGNED_UPLOAD_EXPIRES_SECONDS",
      300,
    );
    const uploadUrl = await getSignedUrl(this.s3, command, { expiresIn });
    const assetBaseUrl = this.config.get<string>("AWS_PUBLIC_ASSET_BASE_URL");
    const region = this.config.get<string>("AWS_REGION", "ap-south-1");
    const fileUrl = assetBaseUrl
      ? `${assetBaseUrl.replace(/\/+$/, "")}/${key}`
      : `https://${bucket}.s3.${region}.amazonaws.com/${key}`;

    return { uploadUrl, fileUrl, key, expiresIn };
  }

  private assertRestaurantScope(
    restaurantId: string,
    user: AuthenticatedUser,
  ): void {
    if (user.role === UserRole.SUPER_ADMIN) {
      return;
    }

    if (user.restaurantId !== restaurantId) {
      throw new ForbiddenException("Restaurant access denied.");
    }
  }
}
