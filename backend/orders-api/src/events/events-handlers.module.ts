import { Module, OnModuleInit } from '@nestjs/common';
import { SearchModule } from '../search/search.module';
import { EventsCoreModule } from './events-core.module';
import { AlgoliaProductEventHandler } from './handlers/algolia-product-event.handler';
import { AnalyticsPlaceholderHandler } from './handlers/analytics-placeholder.handler';
import { NotificationHookService } from '../notifications/notification-hook.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { ChatConversationCreatedHandler } from './handlers/chat/chat-conversation-created.handler';
import { ChatMessageReadHandler } from './handlers/chat/chat-message-read.handler';
import { ChatMessageSentHandler } from './handlers/chat/chat-message-sent.handler';
import { ChatEventMetricsService } from './handlers/chat/chat-event-metrics.service';
import { AiAssistantHookService } from './handlers/chat/ai-assistant-hook.service';
import { ServiceRequestsModule } from '../service-requests/service-requests.module';
import { ServiceRequestNotificationHandler } from './handlers/service-requests/service-request-notification.handler';
import { ServiceRequestAutoAssignHandler } from './handlers/service-requests/service-request-auto-assign.handler';
import { RatingCreatedHandler } from './handlers/ratings/rating-created.handler';

@Module({
  imports: [EventsCoreModule, SearchModule, ServiceRequestsModule, NotificationsModule],
  providers: [
    AlgoliaProductEventHandler,
    AnalyticsPlaceholderHandler,
    NotificationHookService,
    AiAssistantHookService,
    ChatEventMetricsService,
    ChatMessageSentHandler,
    ChatMessageReadHandler,
    ChatConversationCreatedHandler,
    ServiceRequestNotificationHandler,
    ServiceRequestAutoAssignHandler,
    RatingCreatedHandler,
  ],
})
export class EventsHandlersModule implements OnModuleInit {
  constructor(
    private readonly algoliaProduct: AlgoliaProductEventHandler,
    private readonly analytics: AnalyticsPlaceholderHandler,
    private readonly chatMessageSent: ChatMessageSentHandler,
    private readonly chatMessageRead: ChatMessageReadHandler,
    private readonly chatConversation: ChatConversationCreatedHandler,
    private readonly serviceRequestNotifications: ServiceRequestNotificationHandler,
    private readonly serviceRequestAutoAssign: ServiceRequestAutoAssignHandler,
    private readonly ratingCreated: RatingCreatedHandler,
  ) {}

  onModuleInit(): void {
    this.algoliaProduct.register();
    this.analytics.register();
    this.chatMessageSent.register();
    this.chatMessageRead.register();
    this.chatConversation.register();
    this.serviceRequestNotifications.register();
    this.serviceRequestAutoAssign.register();
    this.ratingCreated.register();
  }
}
