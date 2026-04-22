import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { IsNotEmpty, IsObject, IsOptional, IsString } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { UsersService } from '../users/users.service';
import { NotificationInboxService } from './notification-inbox.service';

class InternalNotificationRecordDto {
  @IsString()
  @IsNotEmpty()
  userId!: string;

  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsString()
  @IsNotEmpty()
  body!: string;

  @IsString()
  @IsNotEmpty()
  type!: string;

  @IsOptional()
  @IsString()
  referenceId?: string;

  @IsOptional()
  @IsString()
  eventId?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

class InternalNotificationByEmailDto {
  @IsString()
  @IsNotEmpty()
  email!: string;

  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsString()
  @IsNotEmpty()
  body!: string;

  @IsString()
  @IsNotEmpty()
  type!: string;

  @IsOptional()
  @IsString()
  referenceId?: string;

  @IsOptional()
  @IsString()
  eventId?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

class InternalBroadcastAdminsDto {
  @IsString()
  @IsNotEmpty()
  title!: string;

  @IsString()
  @IsNotEmpty()
  body!: string;

  @IsString()
  @IsNotEmpty()
  type!: string;

  @IsOptional()
  @IsString()
  referenceId?: string;

  @IsOptional()
  @IsString()
  eventId?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}

@Controller('internal/notifications')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none' })
export class NotificationsInternalController {
  constructor(
    private readonly inbox: NotificationInboxService,
    private readonly users: UsersService,
  ) {}

  /** Single-user inbox row (PostgreSQL); push delivery is triggered by the caller (e.g. Cloud Function). */
  @Post()
  record(@Body() body: InternalNotificationRecordDto) {
    return this.inbox.insertRecord({
      userId: body.userId,
      title: body.title,
      body: body.body,
      type: body.type,
      eventId: body.eventId,
      referenceId: body.referenceId,
      metadata: body.metadata,
    });
  }

  @Post('broadcast-admins')
  async broadcastAdmins(@Body() body: InternalBroadcastAdminsDto) {
    const uids = await this.users.listAdminFirebaseUids();
    const ids: string[] = [];
    for (const uid of uids) {
      const r = await this.inbox.insertRecord({
        userId: uid,
        title: body.title,
        body: body.body,
        type: body.type,
        eventId: body.eventId != null ? `${body.eventId}:${uid}` : undefined,
        referenceId: body.referenceId,
        metadata: body.metadata,
      });
      ids.push(r.id);
    }
    return { ok: true as const, targets: uids, ids };
  }

  @Post('by-email')
  async byEmail(@Body() body: InternalNotificationByEmailDto) {
    const uid = await this.users.findFirebaseUidByEmailNormalized(body.email);
    if (!uid) {
      return { ok: false as const, reason: 'user_not_found' as const };
    }
    const r = await this.inbox.insertRecord({
      userId: uid,
      title: body.title,
      body: body.body,
      type: body.type,
      eventId: body.eventId,
      referenceId: body.referenceId,
      metadata: body.metadata,
    });
    return { ok: true as const, userId: uid, id: r.id };
  }
}
