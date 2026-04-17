import { Injectable, OnModuleInit } from '@nestjs/common';
import { CatalogPgService } from '../search/catalog-pg.service';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import { OrdersService } from '../orders/orders.service';
import { TenantContextService } from '../identity/tenant-context.service';
import { DomainServiceRegistry } from './domain-service-registry.service';

@Injectable()
export class DomainRegistryBootstrapService implements OnModuleInit {
  constructor(
    private readonly registry: DomainServiceRegistry,
    private readonly orders: OrdersService,
    private readonly catalog: CatalogPgService,
    private readonly bus: DomainEventEmitterService,
    private readonly users: TenantContextService,
  ) {}

  onModuleInit(): void {
    this.registry.registerOrders(this.orders);
    this.registry.registerProducts(this.catalog);
    this.registry.registerEventBus(this.bus);
    this.registry.registerUsers(this.users);
  }
}
