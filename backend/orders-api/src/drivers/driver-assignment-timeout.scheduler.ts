import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DriversService } from './drivers.service';

/**
 * Every 10s: auto-reject assignments unaccepted after 30s (see DriversService.processStaleAssignedOrders).
 * Opt out: DELIVERY_ASSIGNMENT_TIMEOUT_ENABLED=0
 */
@Injectable()
export class DriverAssignmentTimeoutScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(DriverAssignmentTimeoutScheduler.name);
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly drivers: DriversService) {}

  onModuleInit(): void {
    if (process.env.DELIVERY_ASSIGNMENT_TIMEOUT_ENABLED?.trim() === '0') {
      this.logger.log('DELIVERY_ASSIGNMENT_TIMEOUT_ENABLED=0 — assignment timeout scheduler off');
      return;
    }
    this.timer = setInterval(() => {
      void this.drivers.processStaleAssignedOrders().catch((e) => {
        this.logger.warn(
          JSON.stringify({
            kind: 'assignment_timeout_tick_failed',
            error: e instanceof Error ? e.message : String(e),
          }),
        );
      });
    }, 10_000);
  }

  onModuleDestroy(): void {
    if (this.timer != null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}
