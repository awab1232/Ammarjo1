import { Module } from '@nestjs/common';
import { EventsCoreModule } from '../events/events-core.module';
import { ApiGatewayModule } from '../gateway/api-gateway.module';
import { IdentityModule } from '../identity/identity.module';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { ChatEventBridgeController, ChatEventsPublicController } from './chat-event-bridge.controller';
import { ChatEventBridgeService } from './chat-event-bridge.service';

@Module({
  imports: [EventsCoreModule, ApiGatewayModule, IdentityModule],
  controllers: [ChatEventBridgeController, ChatEventsPublicController],
  providers: [ChatEventBridgeService, InternalApiKeyGuard],
})
export class ChatEventBridgeModule {}

