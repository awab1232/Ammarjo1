import { Injectable } from '@nestjs/common';
import type { Request } from 'express';
import { getGatewayContext } from '../../identity/tenant-context.storage';
import { TenantRegionService } from '../tenant/tenant-region.service';
import { defaultRegionId, isRegionRoutingEnabled } from './region.config';

export type RegionRequestMeta = {
  /** Hint from edge / caller (e.g. header already parsed). */
  regionHint?: string | null;
};

function firstHeader(req: Request, name: string): string | undefined {
  const v = req.headers[name.toLowerCase()];
  if (Array.isArray(v)) {
    return v[0]?.trim();
  }
  return typeof v === 'string' ? v.trim() : undefined;
}

/**
 * Resolves logical region for the current deployment and request. Inactive when
 * REGION_ROUTING_ENABLED is not set (static default only).
 */
@Injectable()
export class RegionService {
  constructor(private readonly tenantRegions: TenantRegionService) {}

  resolveRegionFromRequest(req: Request): string {
    if (!isRegionRoutingEnabled()) {
      return defaultRegionId();
    }
    const fromHeader =
      firstHeader(req, 'x-region') ||
      firstHeader(req, 'x-forwarded-region') ||
      firstHeader(req, 'cf-region') ||
      firstHeader(req, 'x-vercel-ip-country-region'); // optional edge hints
    const trimmed = fromHeader?.trim();
    if (trimmed) {
      return trimmed;
    }
    return defaultRegionId();
  }

  /** Region attached to gateway ALS (after middleware), or static default. */
  getCurrentRegion(): string {
    const g = getGatewayContext();
    if (g?.region != null && g.region !== '') {
      return g.region;
    }
    return defaultRegionId();
  }

  /**
   * True when the tenant's preferred region (if any) matches this process region.
   * When no mapping exists, returns true (backward compatible single-region).
   */
  isLocalRegion(tenantId: string | null | undefined): boolean {
    const pref = this.tenantRegions.resolveTenantRegion(tenantId);
    if (pref == null) {
      return true;
    }
    return pref === this.getCurrentRegion();
  }

  /**
   * Best region for routing hints: tenant override (when enforcement + map),
   * then request meta, then current/default.
   */
  resolveBestRegion(tenantId: string | null | undefined, meta?: RegionRequestMeta): string {
    if (!isRegionRoutingEnabled()) {
      return defaultRegionId();
    }
    const mapped = this.tenantRegions.resolveTenantRegion(tenantId);
    if (mapped != null) {
      return mapped;
    }
    const hint = meta?.regionHint?.trim();
    if (hint) {
      return hint;
    }
    return this.getCurrentRegion();
  }
}
