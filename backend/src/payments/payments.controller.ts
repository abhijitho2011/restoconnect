import { Body, Controller, Post } from "@nestjs/common";
import { CreateRazorpayOrderDto } from "./dto/create-razorpay-order.dto";
import { PaymentsService } from "./payments.service";

@Controller("payments")
export class PaymentsController {
  constructor(private readonly paymentsService: PaymentsService) {}

  @Post("razorpay/orders")
  createRazorpayOrder(@Body() dto: CreateRazorpayOrderDto) {
    return this.paymentsService.createRazorpayOrder(dto);
  }
}
