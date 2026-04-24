import { Module } from "@nestjs/common";
import {
  MenuCategoriesController,
  MenuItemsController,
  PublicMenuController,
} from "./menu.controller";
import { MenuService } from "./menu.service";

@Module({
  controllers: [
    MenuCategoriesController,
    MenuItemsController,
    PublicMenuController,
  ],
  providers: [MenuService],
})
export class MenuModule {}
