import { Injectable, Logger } from '@nestjs/common';
import { NotificationsService } from './notifications.service';

@Injectable()
export class NotificationHookService {
  private readonly logger = new Logger(NotificationHookService.name);

  constructor(private readonly notifications: NotificationsService) {}

  notifyNewMessage(payload: Record<string, unknown>): void {
    setImmediate(() => {
      this.logger.log(
        JSON.stringify({
          kind: 'notification_hook_new_message',
          payload,
        }),
      );
      const conversationId =
        typeof payload['conversationId'] === 'string' ? payload['conversationId'].trim() : '';
      const senderId = typeof payload['senderId'] === 'string' ? payload['senderId'] : null;
      const targetUserId =
        typeof payload['targetUserId'] === 'string' ? payload['targetUserId'].trim() : null;
      if (conversationId && targetUserId) {
        this.notifications.notifyNewMessage({ conversationId, senderId, targetUserId });
      }
    });
  }

  notifyConversationCreated(payload: Record<string, unknown>): void {
    setImmediate(() => {
      this.logger.log(
        JSON.stringify({
          kind: 'notification_hook_conversation_created',
          payload,
        }),
      );
    });
  }
}

