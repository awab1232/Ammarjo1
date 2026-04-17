import { Injectable, Logger } from '@nestjs/common';
import type {
  NewMessageNotificationInput,
  NotificationPayload,
  RatingReceivedNotificationInput,
  ServiceAssignedNotificationInput,
  ServiceCompletedNotificationInput,
} from './notifications.types';
import { FcmClientService } from './fcm-client.service';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly deviceTokensByUser = new Map<string, Set<string>>();
  private readonly notificationsEnabled = (process.env.NOTIFICATIONS_ENABLED ?? 'false').trim().toLowerCase() === 'true';

  constructor(private readonly fcm: FcmClientService) {}

  registerDeviceToken(userId: string, token: string): void {
    if (!this.notificationsEnabled) return;
    const uid = userId.trim();
    const t = token.trim();
    if (!uid || !t) return;
    const bucket = this.deviceTokensByUser.get(uid) ?? new Set<string>();
    bucket.add(t);
    this.deviceTokensByUser.set(uid, bucket);
  }

  notifyNewMessage(input: NewMessageNotificationInput): void {
    const targetUserId = input.targetUserId?.trim();
    if (!targetUserId) return;
    const payload: NotificationPayload = {
      title: 'New Message',
      body: 'You have a new chat message',
      data: {
        type: 'message.sent',
        conversationId: input.conversationId,
        senderId: input.senderId ?? '',
      },
    };
    this.dispatchToUser(targetUserId, payload, 'notification_new_message');
  }

  notifyServiceAssigned(input: ServiceAssignedNotificationInput): void {
    const payload: NotificationPayload = {
      title: 'Service Assigned',
      body: 'A service request was assigned to you',
      data: {
        type: 'service_request.assigned',
        requestId: input.requestId,
      },
    };
    this.dispatchToUser(input.technicianId, payload, 'notification_service_assigned');
  }

  notifyServiceCompleted(input: ServiceCompletedNotificationInput): void {
    const payload: NotificationPayload = {
      title: 'Service Completed',
      body: 'Your service request was marked as completed',
      data: {
        type: 'service_request.completed',
        requestId: input.requestId,
      },
    };
    this.dispatchToUser(input.customerId, payload, 'notification_service_completed');
  }

  notifyRatingReceived(input: RatingReceivedNotificationInput): void {
    const targetUserId = input.targetUserId?.trim();
    if (!targetUserId) return;
    const payload: NotificationPayload = {
      title: 'New Rating',
      body: 'You received a new rating',
      data: {
        type: 'rating.created',
        targetId: input.targetId,
        targetType: input.targetType,
      },
    };
    this.dispatchToUser(targetUserId, payload, 'notification_rating_received');
  }

  private dispatchToUser(userId: string, payload: NotificationPayload, kind: string): void {
    if (!this.notificationsEnabled) {
      this.logger.debug(JSON.stringify({ kind: 'notifications_disabled_noop', userId }));
      return;
    }
    setImmediate(() => {
      const tokens = [...(this.deviceTokensByUser.get(userId)?.values() ?? [])];
      if (process.env.DEBUG_EVENTS?.trim() === '1') {
        this.logger.debug(JSON.stringify({ kind: `${kind}_debug`, userId, payload, tokensCount: tokens.length }));
      }
      if (tokens.length === 0) return;
      if (tokens.length === 1) {
        void this.fcm.sendToUser(userId, tokens[0], payload);
      } else {
        void this.fcm.sendToMultiple([userId], tokens, payload);
      }
    });
  }
}

