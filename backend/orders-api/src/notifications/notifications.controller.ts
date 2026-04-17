import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { IsNotEmpty, IsString } from 'class-validator';
import { NotificationInboxService } from './notification-inbox.service';
import { NotificationsService } from './notifications.service';

class RegisterDeviceTokenDto {
  @IsString()
  @IsNotEmpty()
  token!: string;
}

@Controller('notifications')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 240 } })
export class NotificationsController {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly inbox: NotificationInboxService,
  ) {}

  @Post('register-device')
  @RequirePermissions('orders.write')
  registerDevice(@Req() req: RequestWithFirebase, @Body() body: RegisterDeviceTokenDto) {
    this.notifications.registerDeviceToken(req.firebaseUid!, body.token);
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
    return this.inbox.list(req.firebaseUid!, Number.isFinite(limit) ? limit : 50, Number.isFinite(offset) ? offset : 0);
  }

  @Patch(':id/read')
  @RequirePermissions('orders.write')
  markRead(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    return this.inbox.markRead(req.firebaseUid!, id);
  }
}

