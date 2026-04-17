import { Module } from '@nestjs/common';
import { EventsCoreModule } from '../events/events-core.module';
import { IdentityModule } from '../identity/identity.module';
import { OrdersModule } from '../orders/orders.module';
import { SearchModule } from '../search/search.module';
import { ArchitectureHealthService } from './architecture-health.service';
import { ArchitectureInternalController } from './architecture-internal.controller';
import { DomainBoundaryService } from './domain-boundary.service';
import { DomainRegistryBootstrapService } from './domain-registry-bootstrap.service';
import { DomainServiceRegistry } from './domain-service-registry.service';

@Module({
  imports: [OrdersModule, SearchModule, EventsCoreModule, IdentityModule],
  controllers: [ArchitectureInternalController],
  providers: [
    DomainServiceRegistry,
    DomainBoundaryService,
    ArchitectureHealthService,
    DomainRegistryBootstrapService,
  ],
  exports: [DomainServiceRegistry, DomainBoundaryService, ArchitectureHealthService],
})
export class ArchitectureModule {}
