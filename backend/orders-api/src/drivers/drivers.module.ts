import { Module, forwardRef } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { FirebaseAuthGuard } from '../auth/firebase-auth.guard';
import { DriversController } from './drivers.controller';
import { DriversService } from './drivers.service';
import { DriverAssignmentTimeoutScheduler } from './driver-assignment-timeout.scheduler';
import { NoDriverAutoRetryScheduler } from './no-driver-auto-retry.scheduler';

@Module({
  imports: [forwardRef(() => OrdersModule), forwardRef(() => NotificationsModule)],
  controllers: [DriversController],
  providers: [DriversService, DriverAssignmentTimeoutScheduler, NoDriverAutoRetryScheduler, FirebaseAuthGuard],
  exports: [DriversService],
})
export class DriversModule {}
