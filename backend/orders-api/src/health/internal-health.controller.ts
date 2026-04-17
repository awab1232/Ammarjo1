import { Controller, Get, UseGuards } from '@nestjs/common';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';
import { RedisClientService } from '../infrastructure/redis/redis-client.service';
import { isRedisInfrastructureEnabled } from '../infrastructure/redis/redis.config';
import { OrdersService } from '../orders/orders.service';

/**
 * Detailed infra status — internal API key only (same sensitivity as previous public /health body).
 */
@Controller('internal/health')
@UseGuards(InternalApiKeyGuard)
export class InternalHealthController {
  constructor(
    private readonly orders: OrdersService,
    private readonly redis: RedisClientService,
  ) {}

  @Get('detailed')
  async detailed() {
    const pgConfigured = this.orders.isOrderStorageConfigured();
    const pgPing = pgConfigured
      ? await this.orders.pingOrderStorage()
      : { ok: false as const, error: 'not_configured' as const };
    const pgOk = pgConfigured ? pgPing.ok : null;

    return {
      ok: true,
      service: 'orders-api',
      database: pgOk ? 'ok' : 'degraded',
      redis: !isRedisInfrastructureEnabled() ? 'disabled' : this.redis.isReady() ? 'ok' : 'degraded',
      postgresql: {
        configured: pgConfigured,
        ok: pgOk,
        ...(pgPing.error != null ? { error: pgPing.error } : {}),
      },
    };
  }
}
