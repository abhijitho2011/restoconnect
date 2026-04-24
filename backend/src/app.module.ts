import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { WinstonModule } from "nest-winston";
import * as winston from "winston";
import { AuthModule } from "./auth/auth.module";
import { HealthModule } from "./health/health.module";
import { MenuModule } from "./menu/menu.module";
import { OrdersModule } from "./orders/orders.module";
import { PaymentsModule } from "./payments/payments.module";
import { PrismaModule } from "./prisma/prisma.module";
import { RestaurantsModule } from "./restaurants/restaurants.module";
import { TablesModule } from "./tables/tables.module";
import { UploadsModule } from "./uploads/uploads.module";
import { UsersModule } from "./users/users.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    WinstonModule.forRoot({
      level: process.env.NODE_ENV === "production" ? "info" : "debug",
      format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.errors({ stack: true }),
        winston.format.json(),
      ),
      transports: [new winston.transports.Console()],
    }),
    PrismaModule,
    AuthModule,
    RestaurantsModule,
    TablesModule,
    MenuModule,
    OrdersModule,
    UploadsModule,
    UsersModule,
    PaymentsModule,
    HealthModule,
  ],
})
export class AppModule {}
