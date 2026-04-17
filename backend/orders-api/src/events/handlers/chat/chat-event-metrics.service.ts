import { Injectable } from '@nestjs/common';
import type { ChatConversationType } from './chat-event.types';

@Injectable()
export class ChatEventMetricsService {
  private messageSent = 0;
  private messageRead = 0;
  private conversationCreated = 0;
  private conversationUpdated = 0;
  private readonly conversationsByType = new Map<string, number>();

  recordMessageSent(): void {
    this.messageSent++;
  }

  recordMessageRead(): void {
    this.messageRead++;
  }

  recordConversationCreated(type: ChatConversationType | 'unknown'): void {
    this.conversationCreated++;
    this.conversationsByType.set(type, (this.conversationsByType.get(type) ?? 0) + 1);
  }

  recordConversationUpdated(): void {
    this.conversationUpdated++;
  }
}

