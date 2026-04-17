import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import type { GlobalCountryCode } from '../../architecture/global-region-context.service';
import { isMultiRegionRoutingEnabled } from '../routing/routing.config';
import { isMultiRegionStrategyEnabled, primaryRegionFromEnv } from './region-strategy.config';
import type { RegionHealthMap } from './region-health.service';
import { RegionHealthService } from './region-health.service';

export type FailoverState = {
  activePrimary: 'JO' | 'EG';
  failoverActive: boolean;
  failoverTarget?: 'JO' | 'EG';
};

/**
 * Failover-aware primary selection using cached region health (refresh interval).
 * No effect unless MULTI_REGION_STRATEGY_ENABLED=1 and ENABLE_MULTI_REGION=1.
 */
@Injectable()
export class MultiRegionStrategyService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MultiRegionStrategyService.name);
  private health: RegionHealthMap = { JO: true, EG: true };
  private interval: ReturnType<typeof setInterval> | null = null;
  private readonly refreshMs = Math.max(
    3000,
    Number.parseInt(process.env.REGION_HEALTH_REFRESH_MS?.trim() ?? '8000', 10) || 8000,
  );

  constructor(private readonly regionHealth: RegionHealthService) {}

  onModuleInit(): void {
    if (!isMultiRegionStrategyEnabled() || !isMultiRegionRoutingEnabled()) {
      return;
    }
    void this.refresh();
    this.interval = setInterval(() => void this.refresh(), this.refreshMs);
  }

  onModuleDestroy(): void {
    if (this.interval != null) {
      clearInterval(this.interval);
      this.interval = null;
    }
  }

  private async refresh(): Promise<void> {
    try {
      this.health = await this.regionHealth.getRegionHealth();
    } catch (e) {
      this.logger.debug(`[MultiRegionStrategy] health refresh: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  getPrimaryRegion(): 'JO' | 'EG' {
    return primaryRegionFromEnv();
  }

  /**
   * Where writes should go: prefer configured primary if healthy, else the other region if healthy.
   */
  resolveWriteRegion(): 'JO' | 'EG' {
    if (!isMultiRegionStrategyEnabled() || !isMultiRegionRoutingEnabled()) {
      return this.getPrimaryRegion();
    }
    const primary = this.getPrimaryRegion();
    const other: 'JO' | 'EG' = primary === 'JO' ? 'EG' : 'JO';
    if (this.health[primary]) {
      return primary;
    }
    if (this.health[other]) {
      return other;
    }
    return primary;
  }

  /**
   * Read routing hint when multi-region + strategy active; otherwise null (caller uses ALS-only routing).
   */
  resolveReadRegion(countryHint: GlobalCountryCode | null): 'JO' | 'EG' | null {
    if (!isMultiRegionRoutingEnabled()) {
      return null;
    }
    if (!isMultiRegionStrategyEnabled()) {
      return null;
    }
    const h = this.health;
    const primary = this.getPrimaryRegion();
    const other: 'JO' | 'EG' = primary === 'JO' ? 'EG' : 'JO';

    if (countryHint === 'JO' && h.JO) {
      return 'JO';
    }
    if (countryHint === 'EG' && h.EG) {
      return 'EG';
    }
    if (countryHint === 'JO' && !h.JO && h.EG) {
      return 'EG';
    }
    if (countryHint === 'EG' && !h.EG && h.JO) {
      return 'JO';
    }

    if (h[primary]) {
      return primary;
    }
    if (h[other]) {
      return other;
    }
    if (h.JO) {
      return 'JO';
    }
    if (h.EG) {
      return 'EG';
    }
    return primary;
  }

  getFailoverState(): FailoverState {
    const primary = this.getPrimaryRegion();
    const write = this.resolveWriteRegion();
    const failoverActive = write !== primary;
    return {
      activePrimary: write,
      failoverActive,
      ...(failoverActive ? { failoverTarget: write } : {}),
    };
  }

  /** Latest cached health (sync) for dashboards. */
  getCachedRegionHealth(): RegionHealthMap {
    return { ...this.health };
  }
}
