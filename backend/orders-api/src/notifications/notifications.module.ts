import { Module } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { FcmClientService } from './fcm-client.service';
import { NotificationInboxService } from './notification-inbox.service';
import { NotificationsController } from './notifications.controller';
import { NotificationsInternalController } from './notifications-internal.controller';
import { NotificationDevicesService } from './notification-devices.service';
import { NotificationQueueService } from './notification-queue.service';
import { NotificationQueueWorker } from './notification-queue.worker';
import { OrdersModule } from '../orders/orders.module';

@Module({
  imports: [OrdersModule],
  controllers: [NotificationsController, NotificationsInternalController],
  providers: [
    NotificationsService,
    FcmClientService,
    NotificationInboxService,
    NotificationDevicesService,
    NotificationQueueService,
    NotificationQueueWorker,
  ],
  exports: [
    NotificationsService,
    FcmClientService,
    NotificationInboxService,
    NotificationDevicesService,
    NotificationQueueService,
  ],
})
export class NotificationsModule {}

