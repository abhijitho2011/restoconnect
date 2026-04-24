import { Injectable, ServiceUnavailableException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Razorpay from "razorpay";
import { CreateRazorpayOrderDto } from "./dto/create-razorpay-order.dto";

@Injectable()
export class PaymentsService {
  constructor(private readonly config: ConfigService) {}

  async createRazorpayOrder(dto: CreateRazorpayOrderDto) {
    const keyId = this.config.get<string>("RAZORPAY_KEY_ID");
    const keySecret = this.config.get<string>("RAZORPAY_KEY_SECRET");

    if (!keyId || !keySecret) {
      throw new ServiceUnavailableException(
        "Razorpay credentials are not configured.",
      );
    }

    const razorpay = new Razorpay({ key_id: keyId, key_secret: keySecret });
    return razorpay.orders.create({
      amount: dto.amountPaise,
      currency: dto.currency ?? "INR",
      receipt: dto.receipt,
      notes: dto.notes,
    });
  }
}
