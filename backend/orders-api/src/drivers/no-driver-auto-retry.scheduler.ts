import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { DriversService } from './drivers.service';

/**
 * Every 30s: pick orders stuck in no_driver_found for 60s+ and re-run auto-assign (max 2 automatic retries).
 * Opt out: DELIVERY_NO_DRIVER_AUTO_RETRY_ENABLED=0
 */
@Injectable()
export class NoDriverAutoRetryScheduler implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(NoDriverAutoRetryScheduler.name);
  private timer: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly drivers: DriversService) {}

  onModuleInit(): void {
    if (process.env.DELIVERY_NO_DRIVER_AUTO_RETRY_ENABLED?.trim() === '0') {
      this.logger.log('DELIVERY_NO_DRIVER_AUTO_RETRY_ENABLED=0 — no-driver auto-retry off');
      return;
    }
    this.timer = setInterval(() => {
      void this.drivers.processNoDriverAutoRetries().catch((e) => {
        this.logger.warn(
          JSON.stringify({
            kind: 'no_driver_auto_retry_tick_failed',
            error: e instanceof Error ? e.message : String(e),
          }),
        );
      });
    }, 30_000);
  }

  onModuleDestroy(): void {
    if (this.timer != null) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }
}
