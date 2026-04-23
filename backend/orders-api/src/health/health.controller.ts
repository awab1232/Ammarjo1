import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { OrdersService } from '../orders/orders.service';

/** Public liveness only — no DB/Redis/credential hints (see GET /internal/health/detailed). */
@Controller()
export class HealthController {
  constructor(private readonly orders: OrdersService) {}

  @Get('health')
  async health() {
    const dbConfigured = this.orders.isOrderStorageConfigured();
    const dbPing = dbConfigured
      ? await this.orders.pingOrderStorage()
      : { ok: false as const, error: 'not_configured' as const };
    if (!dbConfigured || !dbPing.ok) {
      throw new ServiceUnavailableException({
        ok: false,
        service: 'orders-api',
        database: 'degraded',
        reason: dbConfigured ? (dbPing.error ?? 'connect_failed') : 'not_configured',
      });
    }
    return {
      ok: true,
      service: 'orders-api',
      database: 'ok',
    };
  }
}
