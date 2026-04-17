import { Controller, Get, UseGuards } from '@nestjs/common';
import { OrderMetricsService } from '../orders/order-metrics.service';
import { InternalApiKeyGuard } from '../search/internal-api-key.guard';

/**
 * Order shadow metrics — **internal only**. Requires `x-internal-api-key` (no Firebase / admin path).
 */
@Controller('internal')
export class MetricsController {
  constructor(private readonly orderMetrics: OrderMetricsService) {}

  @Get('metrics')
  @UseGuards(InternalApiKeyGuard)
  getMetrics() {
    const s = this.orderMetrics.getSnapshot();
    return {
      totalOrders: s.totalOrders,
      failedValidations: s.failedValidations,
      successRate: s.successRate,
      errorsLogged: s.errorsLogged,
      writeSource: s.writeSource,
    };
  }
}
