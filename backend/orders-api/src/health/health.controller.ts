import { Controller, Get } from '@nestjs/common';

/** Public liveness only — no DB/Redis/credential hints (see GET /internal/health/detailed). */
@Controller()
export class HealthController {
  @Get('health')
  health() {
    return {
      ok: true,
      service: 'orders-api',
    };
  }
}
