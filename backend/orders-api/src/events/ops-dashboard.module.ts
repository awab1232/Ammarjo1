import { Module } from '@nestjs/common';
import { InfrastructureModule } from '../infrastructure/infrastructure.module';
import { GlobalHealthController } from '../infrastructure/health/global-health.controller';
import { ProductionReadinessService } from '../infrastructure/health/production-readiness.service';
import { GlobalSystemHealthService } from '../infrastructure/health/global-system-health.service';
import { OrdersModule } from '../orders/orders.module';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { EventsCoreModule } from './events-core.module';
import { OpsDashboardController } from './ops-dashboard.controller';

@Module({
  imports: [InfrastructureModule, EventsCoreModule, OrdersModule],
  controllers: [OpsDashboardController, GlobalHealthController],
  providers: [InternalApiKeyGuard, GlobalSystemHealthService, ProductionReadinessService],
})
export class OpsDashboardModule {}
