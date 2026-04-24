import {
  IsIn,
  IsMimeType,
  IsOptional,
  IsString,
  IsUUID,
  Length,
} from "class-validator";

export class CreateSignedUploadDto {
  @IsUUID()
  restaurantId!: string;

  @IsIn(["images", "ar-models"])
  folder!: "images" | "ar-models";

  @IsString()
  @Length(1, 160)
  fileName!: string;

  @IsMimeType()
  contentType!: string;

  @IsOptional()
  @IsString()
  @Length(1, 80)
  entityId?: string;
}
