import { Injectable } from '@nestjs/common';
import type { IEventBus } from './contracts/i-event-bus';
import type { IOrderService } from './contracts/i-order.service';
import type { IProductService } from './contracts/i-product.service';
import type { IUserService } from './contracts/i-user.service';

/**
 * In-process registry for domain facades (future: replace with HTTP/gRPC clients per service).
 */
@Injectable()
export class DomainServiceRegistry {
  private orders?: IOrderService;
  private products?: IProductService;
  private eventBus?: IEventBus;
  private users?: IUserService;

  registerOrders(s: IOrderService): void {
    this.orders = s;
  }

  registerProducts(s: IProductService): void {
    this.products = s;
  }

  registerEventBus(s: IEventBus): void {
    this.eventBus = s;
  }

  registerUsers(s: IUserService): void {
    this.users = s;
  }

  getOrders(): IOrderService | undefined {
    return this.orders;
  }

  getProducts(): IProductService | undefined {
    return this.products;
  }

  getEventBus(): IEventBus | undefined {
    return this.eventBus;
  }

  getUsers(): IUserService | undefined {
    return this.users;
  }
}
