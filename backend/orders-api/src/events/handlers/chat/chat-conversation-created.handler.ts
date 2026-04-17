import { Injectable, Logger } from '@nestjs/common';
import { DomainEventNames } from '../../domain-event-names';
import { DomainEventEmitterService } from '../../domain-event-emitter.service';
import type { DomainEventEnvelope } from '../../domain-event.types';
import { NotificationHookService } from '../../../notifications/notification-hook.service';
import { AiAssistantHookService } from './ai-assistant-hook.service';
import { ChatEventMetricsService } from './chat-event-metrics.service';
import { ServiceRequestsService } from '../../../service-requests/service-requests.service';
import {
  asNonEmptyString,
  toConversationType,
  toParticipants,
  type ChatConversationPayload,
} from './chat-event.types';

@Injectable()
export class ChatConversationCreatedHandler {
  private readonly logger = new Logger(ChatConversationCreatedHandler.name);

  constructor(
    private readonly emitter: DomainEventEmitterService,
    private readonly metrics: ChatEventMetricsService,
    private readonly notifications: NotificationHookService,
    private readonly aiHook: AiAssistantHookService,
    private readonly serviceRequests: ServiceRequestsService,
  ) {}

  register(): void {
    this.emitter.subscribe(DomainEventNames.CHAT_CONVERSATION_CREATED, (env: DomainEventEnvelope) => {
      this.onCreated(env as DomainEventEnvelope<ChatConversationPayload>);
    });
  }

  private onCreated(env: DomainEventEnvelope<ChatConversationPayload>): void {
    const conversationId =
      asNonEmptyString(env.payload?.conversationId) ?? asNonEmptyString(env.entityId) ?? 'unknown';
    const type = toConversationType(env.payload?.type);
    const participants = toParticipants(env.payload?.participants);
    this.metrics.recordConversationCreated(type);
    this.logger.log(
      JSON.stringify({
        kind: 'chat_conversation_created',
        conversationId,
        type,
        participants,
      }),
    );
    if (process.env.DEBUG_EVENTS?.trim() === '1') {
      this.logger.debug(
        JSON.stringify({
          kind: 'chat_conversation_created_debug',
          payload: env.payload,
        }),
      );
    }
    this.notifications.notifyConversationCreated({
      conversationId,
      type,
      participants,
    });
    this.aiHook.onConversationCreated({
      conversationId,
      type,
      participants,
    });
    if (type === 'technician_customer') {
      const customerId = asNonEmptyString(env.payload?.customerId);
      const technicianId = asNonEmptyString(env.payload?.technicianId);
      void this.serviceRequests
        .createRequest({
          conversationId,
          description: 'Auto-created from technician conversation',
          customerId: customerId ?? undefined,
          technicianId: technicianId ?? undefined,
        })
        .catch((e: unknown) => {
          this.logger.warn(
            JSON.stringify({
              kind: 'chat_conversation_service_request_autocreate_failed',
              conversationId,
              reason: e instanceof Error ? e.message : String(e),
            }),
          );
        });
    }
  }

}

