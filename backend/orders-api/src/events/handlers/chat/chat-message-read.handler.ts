import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { ChatEventMetricsService } from './chat-event-metrics.service';
import { asNonEmptyString, type ChatMessageReadPayload } from './chat-event.types';

@Injectable()
export class ChatMessageReadHandler {
  private readonly logger = new Logger(ChatMessageReadHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly metrics: ChatEventMetricsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.CHAT_MESSAGE_READ, (env: DomainEventEnvelope) => {
      this.handle(env as DomainEventEnvelope<ChatMessageReadPayload>);
    });
  }

  private handle(env: DomainEventEnvelope<ChatMessageReadPayload>): void {
    const conversationId =
      asNonEmptyString(env.payload?.conversationId) ?? asNonEmptyString(env.entityId) ?? 'unknown';
    const readerId = asNonEmptyString(env.payload?.readerId);
    this.metrics.recordMessageRead();
    this.logger.log(
      JSON.stringify({
        kind: 'chat_message_read',
        conversationId,
        readerId,
      }),
    );
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(
        JSON.stringify({
          kind: 'chat_message_read_debug',
          payload: env.payload,
        }),
      );
    }
  }
}

