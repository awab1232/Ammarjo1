import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_GUARD, ModuleRef } from '@nestjs/core';
import type { NextFunction, Request, Response } from 'express';
import { ArchitectureModule } from './architecture/architecture.module';
import { ApiGatewayModule } from './gateway/api-gateway.module';
import { ApiGatewayMiddleware } from './gateway/api-gateway.middleware';
import { InfrastructureModule } from './infrastructure/infrastructure.module';
import { IdentityModule } from './identity/identity.module';
import { TenantContextGuard } from './identity/tenant-context.guard';
import { RbacGuard } from './identity/rbac.guard';
import { ApiPolicyGuard } from './gateway/api-policy.guard';
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
import { TelegramBotModule } from './telegram/telegram-bot.module';
import { BlogController } from './blog/blog.controller';
import { HomeModule } from './home/home.module';
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
    TelegramBotModule,
    HomeModule,
  ],
  controllers: [AppController, HealthController, InternalHealthController, BlogController],
  providers: [
    { provide: APP_GUARD, useClass: TenantContextGuard },
    { provide: APP_GUARD, useClass: ApiPolicyGuard },
    { provide: APP_GUARD, useClass: RbacGuard },
  ],
})
export class AppModule implements NestModule {
  constructor(private readonly moduleRef: ModuleRef) {}

  configure(consumer: MiddlewareConsumer): void {
    const apiGateway = this.moduleRef.get(ApiGatewayMiddleware, { strict: false });
    consumer
      .apply((req: Request, res: Response, next: NextFunction) => apiGateway.use(req, res, next))
      .forRoutes('*');
  }
}
