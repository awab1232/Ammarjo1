import { Injectable } from '@nestjs/common';
import { isTenantRegionEnforcementEnabled } from './tenant-region.config';

/**
 * In-memory tenant → preferred region map (no DB). Safe to extend with admin APIs later.
 */
@Injectable()
export class TenantRegionService {
  private readonly preferred = new Map<string, string>();

  /** Optional override for tests or future control-plane hooks. */
  setPreferredRegion(tenantId: string, region: string): void {
    const t = tenantId.trim();
    if (!t) return;
    this.preferred.set(t, region.trim());
  }

  clearPreferredRegion(tenantId: string): void {
    this.preferred.delete(tenantId.trim());
  }

  /** Returns mapped region when enforcement is on and a mapping exists. */
  resolveTenantRegion(tenantId: string | null | undefined): string | null {
    if (!isTenantRegionEnforcementEnabled() || tenantId == null || tenantId === '') {
      return null;
    }
    return this.preferred.get(tenantId.trim()) ?? null;
  }
}
