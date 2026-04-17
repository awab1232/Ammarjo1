import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { AdminAnalyticsService } from './admin.analytics.service';
import { AdminOnlyGuard } from './admin-only.guard';
import { AdminRestController } from './admin-rest.controller';
import { AdminRestService } from './admin-rest.service';
import { SupportTicketsController } from './support-tickets.controller';
import { AuthModule } from '../auth/auth.module';

@Module({
  imports: [AuthModule],
  controllers: [
    AdminController,
    AdminRestController,
    SupportTicketsController,
  ],
  providers: [AdminAnalyticsService, AdminRestService, AdminOnlyGuard],
})
export class AdminModule {}

