import { Injectable, Logger } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import type {
  NewMessageNotificationInput,
  NotificationPayload,
  RatingReceivedNotificationInput,
  ServiceAssignedNotificationInput,
  ServiceCompletedNotificationInput,
} from './notifications.types';
import { NotificationDevicesService } from './notification-devices.service';
import { NotificationQueueService } from './notification-queue.service';
import { NotificationInboxService } from './notification-inbox.service';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly notificationsEnabled = (process.env.NOTIFICATIONS_ENABLED ?? 'false').trim().toLowerCase() === 'true';

  constructor(
    private readonly users: UsersService,
    private readonly devices: NotificationDevicesService,
    private readonly queue: NotificationQueueService,
    private readonly inbox: NotificationInboxService,
  ) {}

  async registerDeviceToken(userId: string, token: string, platform?: string): Promise<void> {
    // Keep token registry active even when push dispatch is disabled,
    // so enabling notifications later does not require users to re-login.
    await this.devices.registerDeviceToken({ userId, token, platform });
  }

  async unregisterDeviceToken(userId: string, token: string): Promise<void> {
    await this.devices.unregisterDeviceToken({ userId, token });
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
    void this.dispatchToUser(targetUserId, payload, 'notification_new_message');
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
    void this.dispatchToUser(input.technicianId, payload, 'notification_service_assigned');
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
    void this.dispatchToUser(input.customerId, payload, 'notification_service_completed');
  }

  /** Delivery — notify driver (Firebase UID = registered driver auth_uid). */
  notifyDriverNewOrder(driverFirebaseUid: string, orderId: string): void {
    const uid = driverFirebaseUid?.trim();
    if (!uid) return;
    const payload: NotificationPayload = {
      title: 'توصيل',
      body: 'طلب جديد قريب منك',
      data: {
        type: 'delivery.order_assigned',
        orderId: String(orderId),
      },
    };
    void this.dispatchToUser(uid, payload, 'delivery_order_assigned_driver');
  }

  /** Customer — order accepted by driver. */
  notifyCustomerOrderAccepted(customerFirebaseUid: string, orderId: string): void {
    const uid = customerFirebaseUid?.trim();
    if (!uid) return;
    const payload: NotificationPayload = {
      title: 'طلبك',
      body: 'تم قبول الطلب',
      data: {
        type: 'delivery.order_accepted',
        orderId: String(orderId),
      },
    };
    void this.dispatchToUser(uid, payload, 'delivery_order_accepted_customer');
  }

  notifyCustomerDriverEnRoute(customerFirebaseUid: string, orderId: string): void {
    const uid = customerFirebaseUid?.trim();
    if (!uid) return;
    const payload: NotificationPayload = {
      title: 'طلبك',
      body: 'السائق في الطريق',
      data: {
        type: 'delivery.on_the_way',
        orderId: String(orderId),
      },
    };
    void this.dispatchToUser(uid, payload, 'delivery_on_the_way_customer');
  }

  notifyCustomerNoDriverFound(customerFirebaseUid: string, orderId: string): void {
    const uid = customerFirebaseUid?.trim();
    if (!uid) return;
    const payload: NotificationPayload = {
      title: 'التوصيل',
      body: 'لم يتم العثور على سائق حالياً، سنحاول مرة أخرى',
      data: {
        type: 'delivery.no_driver_found',
        orderId: String(orderId),
      },
    };
    void this.dispatchToUser(uid, payload, 'delivery_no_driver_customer');
  }

  /** Best-effort alert to admin dashboards (FCM + structured log). */
  notifyAdminsNoDrivers(orderId: string, reason: string): void {
    this.logger.warn(
      JSON.stringify({
        kind: 'delivery_no_drivers_admin',
        orderId,
        reason,
      }),
    );
    if (!this.notificationsEnabled) {
      return;
    }
    void this.users.listAdminFirebaseUids().then((uids) => {
      for (const adminUid of uids) {
        const payload: NotificationPayload = {
          title: 'توصيل',
          body: `لا يوجد سائق للطلب ${orderId}`,
          data: {
            type: 'delivery.admin_no_drivers',
            orderId: String(orderId),
            reason: String(reason),
          },
        };
        void this.dispatchToUser(adminUid, payload, 'delivery_no_drivers_admin_fcm');
      }
    });
  }

  notifyCustomerOrderDelivered(customerFirebaseUid: string, orderId: string): void {
    const uid = customerFirebaseUid?.trim();
    if (!uid) return;
    const payload: NotificationPayload = {
      title: 'طلبك',
      body: 'تم التسليم',
      data: {
        type: 'delivery.delivered',
        orderId: String(orderId),
      },
    };
    void this.dispatchToUser(uid, payload, 'delivery_delivered_customer');
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
    void this.dispatchToUser(targetUserId, payload, 'notification_rating_received');
  }

  /**
   * Resolves store owner Firebase UID and enqueues push + inbox. Fire-and-forget.
   */
  sendPushToStore(
    storeId: string,
    p: { title: string; body: string; data: Record<string, string> },
  ): void {
    const sid = storeId?.trim();
    if (!sid) return;
    void this.users
      .getStoreOwnerUidByStoreId(sid)
      .then((uid) => {
        if (!uid) return;
        const payload: NotificationPayload = {
          title: p.title,
          body: p.body,
          data: p.data,
        };
        return this.dispatchToUser(uid, payload, 'tender_push_to_store');
      })
      .catch((e) => this.logger.error(`sendPushToStore: ${e instanceof Error ? e.message : String(e)}`));
  }

  private async dispatchToUser(userId: string, payload: NotificationPayload, kind: string): Promise<void> {
    const eventId = this.buildEventId(kind, userId, payload);
    const inbox = await this.inbox.insertRecord({
      userId,
      title: payload.title,
      body: payload.body,
      type: payload.data?.['type'] || kind,
      eventId,
      metadata: payload.data != null ? payload.data : {},
    });
    if (!this.notificationsEnabled) {
      this.logger.warn(
        JSON.stringify({
          kind: 'notifications_push_disabled_inbox_only',
          userId,
          eventId,
        }),
      );
      return;
    }
    const queued = await this.queue.enqueue({
      userId,
      payload: {
        ...payload,
        data: {
          ...(payload.data ?? {}),
          event_id: eventId,
        },
      },
      eventId,
      inboxNotificationId: inbox.id,
    });
    this.logger.log(
      JSON.stringify({
        kind: 'notification_enqueued',
        userId,
        eventId,
        queue: queued,
      }),
    );
  }

  private buildEventId(kind: string, userId: string, payload: NotificationPayload): string {
    const type = payload.data?.['type'] ?? kind;
    const reference =
      payload.data?.['orderId'] ??
      payload.data?.['requestId'] ??
      payload.data?.['conversationId'] ??
      payload.data?.['targetId'] ??
      payload.body;
    return `${type}:${userId}:${reference}`.slice(0, 240);
  }
}

