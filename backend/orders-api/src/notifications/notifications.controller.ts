import { Body, Controller, Get, Logger, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';
import { NotificationInboxService } from './notification-inbox.service';
import { NotificationsService } from './notifications.service';

class RegisterDeviceTokenDto {
  @IsString()
  @IsNotEmpty()
  token!: string;

  @IsString()
  @IsOptional()
  platform?: string;
}

class UnregisterDeviceTokenDto {
  @IsString()
  @IsNotEmpty()
  token!: string;
}

@Controller('notifications')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
export class NotificationsController {
  private readonly logger = new Logger(NotificationsController.name);

  constructor(
    private readonly notifications: NotificationsService,
    private readonly inbox: NotificationInboxService,
  ) {}

  @Post('register-device')
  @RequirePermissions('orders.write')
  async registerDevice(@Req() req: RequestWithFirebase, @Body() body: RegisterDeviceTokenDto) {
    await this.notifications.registerDeviceToken(req.firebaseUid!, body.token, body.platform);
    return { ok: true };
  }

  @Post('unregister-device')
  @RequirePermissions('orders.write')
  async unregisterDevice(@Req() req: RequestWithFirebase, @Body() body: UnregisterDeviceTokenDto) {
    await this.notifications.unregisterDeviceToken(req.firebaseUid!, body.token);
    return { ok: true };
  }

  @Get()
  @RequirePermissions('orders.read')
  list(
    @Req() req: RequestWithFirebase,
    @Query('limit') limitRaw?: string,
    @Query('offset') offsetRaw?: string,
  ) {
    const limit = limitRaw != null && limitRaw.trim() !== '' ? Number.parseInt(limitRaw, 10) : 50;
    const offset = offsetRaw != null && offsetRaw.trim() !== '' ? Number.parseInt(offsetRaw, 10) : 0;
    return this.inbox
      .list(req.firebaseUid!, Number.isFinite(limit) ? limit : 50, Number.isFinite(offset) ? offset : 0)
      .catch((error: unknown) => {
        this.logger.warn(
          `notifications list failed for uid=${req.firebaseUid ?? 'unknown'}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
        return { items: [], total: 0 };
      });
  }

  @Patch(':id/read')
  @RequirePermissions('orders.write')
  markRead(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.inbox.markRead(req.firebaseUid!, id);
  }

  @Get('updates')
  @RequirePermissions('orders.read')
  async updates(
    @Req() req: RequestWithFirebase,
    @Query('since') since?: string,
    @Query('limit') limitRaw?: string,
  ) {
    const limit = limitRaw != null && limitRaw.trim() !== '' ? Number.parseInt(limitRaw, 10) : 20;
    const unread = await this.inbox.unreadCount(req.firebaseUid!);
    if (since == null || since.trim().length === 0) {
      return { unread, items: [] };
    }
    const items = await this.inbox.listSince(req.firebaseUid!, since, Number.isFinite(limit) ? limit : 20);
    return { unread, items };
  }
}

