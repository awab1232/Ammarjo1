import { Module } from '@nestjs/common';
import { NotificationsService } from './notifications.service';
import { FcmClientService } from './fcm-client.service';
import { NotificationInboxService } from './notification-inbox.service';
import { NotificationsController } from './notifications.controller';
import { NotificationsInternalController } from './notifications-internal.controller';

@Module({
  controllers: [NotificationsController, NotificationsInternalController],
  providers: [NotificationsService, FcmClientService, NotificationInboxService],
  exports: [NotificationsService, FcmClientService, NotificationInboxService],
})
export class NotificationsModule {}

