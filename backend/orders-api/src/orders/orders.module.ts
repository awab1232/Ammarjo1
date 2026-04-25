import { Module, forwardRef } from '@nestjs/common';
import { MetricsController } from '../metrics/metrics.controller';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { StoresModule } from '../stores/stores.module';
import { DriversModule } from '../drivers/drivers.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { OrderMetricsService } from './order-metrics.service';
import { OrdersPgService } from './orders-pg.service';
import { OrdersController } from './orders.controller';
import { OrdersListRateLimitGuard } from './orders-list-rate-limit.guard';
import { OrdersService } from './orders.service';

@Module({
  imports: [StoresModule, forwardRef(() => DriversModule), forwardRef(() => NotificationsModule)],
  controllers: [OrdersController, MetricsController],
  providers: [
    OrdersPgService,
    OrdersService,
    OrderMetricsService,
    FirebaseAuthGuard,
    OrdersListRateLimitGuard,
    InternalApiKeyGuard,
  ],
  exports: [OrderMetricsService, OrdersPgService, OrdersService],
})
export class OrdersModule {}
