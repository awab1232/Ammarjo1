import { AsyncLocalStorage } from 'node:async_hooks';
import { Injectable } from '@nestjs/common';
import { defaultCountryCode } from '../infrastructure/routing/routing.config';

export type GlobalCountryCode = 'JO' | 'EG' | 'UNKNOWN';

export type GlobalRegionSnapshot = {
  country: GlobalCountryCode;
  /** Logical region label (e.g. same as country code or cloud region). */
  region: string;
  tenantId?: string;
  /** CDN / edge hints (optional; does not replace `country` from x-country). */
  edge?: {
    country?: GlobalCountryCode;
    region?: string;
    clientLatencyMs?: number;
  };
};

const als = new AsyncLocalStorage<GlobalRegionSnapshot>();

function defaultSnapshot(): GlobalRegionSnapshot {
  const c = defaultCountryCode();
  return {
    country: c,
    region: c,
    tenantId: undefined,
  };
}

/**
 * Request-scoped country/region for data routing (ALS). Safe to call outside ALS: returns defaults.
 */
export function getGlobalRegionContext(): GlobalRegionSnapshot {
  return als.getStore() ?? defaultSnapshot();
}

@Injectable()
export class GlobalRegionContextService {
  runWithContext<T>(snapshot: GlobalRegionSnapshot, fn: () => T): T {
    return als.run(snapshot, fn);
  }

  getSnapshot(): GlobalRegionSnapshot {
    return getGlobalRegionContext();
  }

  patch(patch: Partial<GlobalRegionSnapshot>): void {
    const s = als.getStore();
    if (s) {
      Object.assign(s, patch);
    }
  }
}
