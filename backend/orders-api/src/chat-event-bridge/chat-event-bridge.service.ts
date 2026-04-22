import { Injectable, Logger, Optional } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DomainEventNames } from '../events/domain-event-names';
import { DomainEventEmitterService } from '../events/domain-event-emitter.service';
import type { DomainEventName } from '../events/domain-event-names';
import { TenantContextService } from '../identity/tenant-context.service';
import type {
  ChatConversationCreatedDto,
  ChatMessageReadDto,
  ChatMessageSentDto,
} from './chat-event-bridge.dto';

@Injectable()
export class ChatEventBridgeService {
  private readonly logger = new Logger(ChatEventBridgeService.name);

  constructor(
    private readonly events: DomainEventEmitterService,
    @Optional() private readonly tenant?: TenantContextService,
  ) {}

  private emit(eventType: DomainEventName, dto: Record<string, unknown> & { conversationId: string }): {
    accepted: true;
    trace_id: string;
  } {
    const conversationId = dto.conversationId.trim();
    const senderId = typeof dto.senderId === 'string' ? dto.senderId.trim() || undefined : undefined;
    const tenantSnapshot = this.tenant?.getSnapshot();
    const traceId = tenantSnapshot?.requestTraceId || randomUUID();

    const payload: Record<string, unknown> = {
      ...dto,
      conversationId,
      senderId,
      tenantId:
        (typeof dto.tenantId === 'string' ? dto.tenantId : undefined) ||
        tenantSnapshot?.tenantId ||
        undefined,
      ingestedAt: new Date().toISOString(),
      source: 'firebase_chat_bridge',
    };

    this.events.dispatch(eventType, conversationId, payload, {
      traceId,
      correlationId: conversationId,
      sourceService: 'system',
      idempotencyKey: `chat:${eventType}:${conversationId}:${String(dto.occurredAt ?? '')}`,
    });

    this.logger.log(
      JSON.stringify({
        kind: 'chat_event_ingested',
        event_type: eventType,
        conversationId,
        senderId: senderId ?? null,
        trace_id: traceId,
      }),
    );

    return { accepted: true, trace_id: traceId };
  }

  messageSent(dto: ChatMessageSentDto): { accepted: true; trace_id: string } {
    const out = this.emit(DomainEventNames.CHAT_MESSAGE_SENT, { ...dto });
    this.logger.log(
      JSON.stringify({
        kind: 'chat_message_sent_processed',
        conversationId: dto.conversationId,
        senderId: dto.senderId ?? null,
        receiverId: dto.receiverId ?? dto.targetUserId ?? null,
        messageId: dto.messageId ?? null,
      }),
    );
    return out;
  }

  rejectInvalidMessageSent(input: {
    senderId: string;
    receiverId: string;
    conversationId: string;
    messageId: string;
    messagePreview: string;
  }): { accepted: false; reason: string } {
    this.logger.warn(
      JSON.stringify({
        kind: 'chat_message_sent_invalid_payload',
        ...input,
      }),
    );
    return { accepted: false, reason: 'invalid_payload' };
  }

  conversationCreated(dto: ChatConversationCreatedDto): { accepted: true; trace_id: string } {
    return this.emit(DomainEventNames.CHAT_CONVERSATION_CREATED, { ...dto });
  }

  messageRead(dto: ChatMessageReadDto): { accepted: true; trace_id: string } {
    return this.emit(DomainEventNames.CHAT_MESSAGE_READ, { ...dto });
  }
}

