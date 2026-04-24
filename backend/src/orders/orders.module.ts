import { Module } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import { JwtModule } from "@nestjs/jwt";
import type ms from "ms";
import { OrdersController } from "./orders.controller";
import { OrdersGateway } from "./orders.gateway";
import { OrdersService } from "./orders.service";

@Module({
  imports: [
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.getOrThrow<string>("JWT_SECRET"),
        signOptions: {
          expiresIn: config.get<string>(
            "JWT_EXPIRES_IN",
            "12h",
          ) as ms.StringValue,
        },
      }),
    }),
  ],
  controllers: [OrdersController],
  providers: [OrdersGateway, OrdersService],
  exports: [OrdersGateway],
})
export class OrdersModule {}
