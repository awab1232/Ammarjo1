import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { NotificationsService } from '../../../notifications/notifications.service';
import { ChatEventMetricsService } from './chat-event-metrics.service';
import { asNonEmptyString, toConversationType, type ChatMessageSentPayload } from './chat-event.types';

@Injectable()
export class ChatMessageSentHandler {
  private readonly logger = new Logger(ChatMessageSentHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly metrics: ChatEventMetricsService,
    private readonly notifications: NotificationsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.CHAT_MESSAGE_SENT, (env: DomainEventEnvelope) => {
      this.handle(env as DomainEventEnvelope<ChatMessageSentPayload>);
    });
  }

  private handle(env: DomainEventEnvelope<ChatMessageSentPayload>): void {
    const conversationId =
      asNonEmptyString(env.payload?.conversationId) ?? asNonEmptyString(env.entityId) ?? 'unknown';
    const senderId = asNonEmptyString(env.payload?.senderId);
    const targetUserId = asNonEmptyString(env.payload?.targetUserId);
    const type = toConversationType(env.payload?.type);
    this.metrics.recordMessageSent();
    this.logger.log(
      JSON.stringify({
        kind: 'chat_message_sent',
        conversationId,
        senderId,
        type,
      }),
    );
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(
        JSON.stringify({
          kind: 'chat_message_sent_debug',
          payload: env.payload,
        }),
      );
    }
    this.notifications.notifyNewMessage({ conversationId, senderId, targetUserId });
  }
}

