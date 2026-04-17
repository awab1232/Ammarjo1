import {
  Controller,
  Get,
  HttpException,
  HttpStatus,
  Param,
  Post,
  Query,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { EventOutboxAlertService } from './event-outbox-alert.service';
import { EventOutboxService } from './event-outbox.service';

@Controller('internal/events')
@UseGuards(TenantContextGuard, ApiPolicyGuard, InternalApiKeyGuard)
@ApiPolicy({ auth: false, tenant: 'none', rateLimit: { rpm: 120 } })
export class EventsInternalController {
  constructor(
    private readonly outbox: EventOutboxService,
    private readonly alerts: EventOutboxAlertService,
  ) {}

  private ensureOutbox(): void {
    if (!this.outbox.isReady()) {
      throw new HttpException('Event outbox not configured', HttpStatus.SERVICE_UNAVAILABLE);
    }
  }

  /** Pending + in-flight rows (oldest first). */
  @Get('pending')
  async listPending(@Query('limit') limit?: string) {
    this.ensureOutbox();
    const n = limit != null ? Number.parseInt(String(limit), 10) : 100;
    const items = await this.outbox.listPendingForAdmin(Number.isFinite(n) ? n : 100);
    return { ok: true, count: items.length, items };
  }

  /** Status counts, retry histogram, recent dead-letter rows. */
  @Get('dashboard')
  async dashboard() {
    this.ensureOutbox();
    const stats = await this.outbox.getDashboardStats();
    return { ok: true, ...stats };
  }

  /** Re-queue a single failed event for the worker. */
  @Post('retry/:eventId')
  async retryOne(@Param('eventId') eventId: string) {
    this.ensureOutbox();
    const id = eventId.trim();
    const result = await this.outbox.retryFailedById(id);
    if (!result.ok) {
      throw new HttpException(
        { ok: false, reason: result.reason ?? 'retry_failed' },
        HttpStatus.NOT_FOUND,
      );
    }
    this.alerts.notifyManualRetryOne(id);
    return { ok: true, eventId: id };
  }

  /** Re-queue all failed events. */
  @Post('retry-all-failed')
  async retryAllFailed() {
    this.ensureOutbox();
    const { updated } = await this.outbox.retryAllFailed();
    this.alerts.notifyRetryAllFailed(updated);
    return { ok: true, updated };
  }
}
