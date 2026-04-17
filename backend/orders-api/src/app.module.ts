import { Module } from '@nestjs/common';
import { ArchitectureModule } from './architecture/architecture.module';
import { ApiGatewayModule } from './gateway/api-gateway.module';
import { InfrastructureModule } from './infrastructure/infrastructure.module';
import { IdentityModule } from './identity/identity.module';
import { HealthController } from './health/health.controller';
import { InternalHealthController } from './health/internal-health.controller';
import { EventsCoreModule } from './events/events-core.module';
import { EventsHandlersModule } from './events/events-handlers.module';
import { EventsInternalModule } from './events/events-internal.module';
import { OpsDashboardModule } from './events/ops-dashboard.module';
import { OrdersModule } from './orders/orders.module';
import { SearchModule } from './search/search.module';
import { ChatEventBridgeModule } from './chat-event-bridge/chat-event-bridge.module';
import { ServiceRequestsModule } from './service-requests/service-requests.module';
import { RatingsModule } from './ratings/ratings.module';
import { NotificationsModule } from './notifications/notifications.module';
import { MatchingModule } from './matching/matching.module';
import { AnalyticsModule } from './analytics/analytics.module';
import { AdminModule } from './admin/admin.module';
import { WholesaleModule } from './wholesale/wholesale.module';
import { ChatModule } from './chat/chat.module';
import { StoreBuilderModule } from './store-builder/store-builder.module';
import { StoresModule } from './stores/stores.module';
import { TendersModule } from './tenders/tenders.module';
import { UsersModule } from './users/users.module';
import { AuthModule } from './auth/auth.module';
import { CartModule } from './cart/cart.module';
import { BlogController } from './blog/blog.controller';
import { HomeController } from './home/home.controller';
import { HomeService } from './home/home.service';
import { AppController } from './app.controller';

@Module({
  imports: [
    UsersModule,
    AuthModule,
    CartModule,
    InfrastructureModule,
    ArchitectureModule,
    ApiGatewayModule,
    IdentityModule,
    EventsCoreModule,
    OrdersModule,
    SearchModule,
    ChatEventBridgeModule,
    ServiceRequestsModule,
    RatingsModule,
    NotificationsModule,
    MatchingModule,
    AnalyticsModule,
    AdminModule,
    WholesaleModule,
    ChatModule,
    StoreBuilderModule,
    StoresModule,
    TendersModule,
    EventsHandlersModule,
    EventsInternalModule,
    OpsDashboardModule,
  ],
  controllers: [AppController, HealthController, InternalHealthController, BlogController, HomeController],
  providers: [HomeService],
})
export class AppModule {}
