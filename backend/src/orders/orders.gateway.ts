import { Logger } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from "@nestjs/websockets";
import { Server, Socket } from "socket.io";
import { AuthenticatedUser } from "../common/interfaces/authenticated-user.interface";

@WebSocketGateway({
  cors: { origin: "*", credentials: true },
  transports: ["websocket", "polling"],
})
export class OrdersGateway implements OnGatewayConnection {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(OrdersGateway.name);

  constructor(private readonly jwt: JwtService) {}

  async handleConnection(client: Socket): Promise<void> {
    const token = this.extractToken(client);
    if (token) {
      try {
        const payload = await this.jwt.verifyAsync<AuthenticatedUser>(token);
        client.data.user = payload;
        if (payload.role === "SUPER_ADMIN") {
          await client.join("super-admin");
        }
        if (payload.restaurantId) {
          await client.join(this.restaurantRoom(payload.restaurantId));
        }
      } catch (error) {
        this.logger.warn(`Rejected socket token: ${(error as Error).message}`);
        client.disconnect(true);
        return;
      }
    }

    const restaurantId = this.queryString(client, "restaurantId");
    const tableId = this.queryString(client, "tableId");
    if (restaurantId) {
      await client.join(this.restaurantRoom(restaurantId));
    }
    if (restaurantId && tableId) {
      await client.join(this.tableRoom(restaurantId, tableId));
    }
  }

  @SubscribeMessage("join_table")
  async joinTable(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { restaurantId?: string; tableId?: string },
  ): Promise<{ ok: true }> {
    if (body.restaurantId && body.tableId) {
      await client.join(this.tableRoom(body.restaurantId, body.tableId));
    }
    return { ok: true };
  }

  emitOrderCreated(order: { restaurantId: string; tableId: string }): void {
    this.server
      .to(this.restaurantRoom(order.restaurantId))
      .emit("order_created", order);
    this.server
      .to(this.tableRoom(order.restaurantId, order.tableId))
      .emit("order_created", order);
    this.server.to("super-admin").emit("order_created", order);
  }

  emitOrderUpdated(order: {
    restaurantId: string;
    tableId: string;
    status: string;
  }): void {
    this.server
      .to(this.restaurantRoom(order.restaurantId))
      .emit("order_updated", order);
    this.server
      .to(this.tableRoom(order.restaurantId, order.tableId))
      .emit("order_updated", order);
    this.server.to("super-admin").emit("order_updated", order);
    if (order.status === "SERVED") {
      this.server
        .to(this.restaurantRoom(order.restaurantId))
        .emit("order_completed", order);
      this.server
        .to(this.tableRoom(order.restaurantId, order.tableId))
        .emit("order_completed", order);
      this.server.to("super-admin").emit("order_completed", order);
    }
  }

  private restaurantRoom(restaurantId: string): string {
    return `restaurant:${restaurantId}`;
  }

  private tableRoom(restaurantId: string, tableId: string): string {
    return `restaurant:${restaurantId}:table:${tableId}`;
  }

  private extractToken(client: Socket): string | null {
    const authToken = client.handshake.auth?.token;
    if (typeof authToken === "string" && authToken.length > 0) {
      return authToken;
    }

    const header = client.handshake.headers.authorization;
    if (typeof header === "string" && header.startsWith("Bearer ")) {
      return header.slice("Bearer ".length);
    }

    return null;
  }

  private queryString(client: Socket, key: string): string | null {
    const value = client.handshake.query[key];
    if (typeof value === "string") {
      return value;
    }
    if (Array.isArray(value)) {
      return value[0] ?? null;
    }
    return null;
  }
}
