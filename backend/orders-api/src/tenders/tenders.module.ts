import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { TendersController } from './tenders.controller';
import { TendersService } from './tenders.service';

@Module({
  imports: [AuthModule, NotificationsModule],
  controllers: [TendersController],
  providers: [TendersService],
  exports: [TendersService],
})
export class TendersModule {}
