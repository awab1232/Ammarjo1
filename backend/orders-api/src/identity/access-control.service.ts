import { ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { getTenantContext } from './tenant-context.storage';
import type { TenantContextSnapshot } from './tenant-context.types';
import type { AppRole } from './rbac-roles.config';

/**
 * Centralized authorization helpers (role + tenant scope). Use from controllers/services instead of ad-hoc checks.
 */
@Injectable()
export class AccessControlService {
  requireUid(snap?: TenantContextSnapshot | null): asserts snap is TenantContextSnapshot & { uid: string } {
    const s = snap ?? getTenantContext();
    if (s?.uid == null || s.uid.trim() === '') {
      throw new UnauthorizedException('Authentication required');
    }
  }

  /** Full coupon/promotion rows (includes payload) — platform admins only. */
  isPlatformAdmin(snap: TenantContextSnapshot): boolean {
    const r = snap.activeRole as AppRole;
    return r === 'admin' || r === 'system_internal';
  }

  assertAdmin(snap: TenantContextSnapshot): void {
    if (!this.isPlatformAdmin(snap)) {
      throw new ForbiddenException('Admin access required');
    }
  }

  /**
   * Store-scoped resources: admin sees all; store_owner only own storeId; others denied unless overridden.
   */
  assertStoreOwnershipOrAdmin(snap: TenantContextSnapshot, storeId: string): void {
    const sid = storeId.trim();
    if (!sid) {
      throw new ForbiddenException('store_id required');
    }
    if (this.isPlatformAdmin(snap)) {
      return;
    }
    if ((snap.activeRole as AppRole) === 'store_owner') {
      const ctx = snap.storeId?.trim() ?? '';
      if (ctx && ctx === sid) {
        return;
      }
      throw new ForbiddenException('store_scope_denied');
    }
    throw new ForbiddenException('store_scope_denied');
  }

  /**
   * Wholesaler-scoped row access (wholesalerId on tenant snapshot must match).
   */
  assertWholesalerScope(snap: TenantContextSnapshot, wholesalerId: string): void {
    const wid = wholesalerId.trim();
    if (!wid) {
      throw new ForbiddenException('wholesaler_id required');
    }
    if (this.isPlatformAdmin(snap)) {
      return;
    }
    const r = String(snap.activeRole).toLowerCase();
    const isWholesaleStoreOwner =
      r === 'store_owner' && String(snap.storeType ?? '').trim().toLowerCase() === 'wholesale';
    if (r === 'wholesaler' || r === 'wholesaler_owner' || isWholesaleStoreOwner) {
      const ctx = snap.wholesalerId?.trim() ?? '';
      if (ctx && ctx === wid) {
        return;
      }
    }
    throw new ForbiddenException('wholesaler_scope_denied');
  }

  /**
   * Technician: resource must belong to caller (compare technician email/id from domain payload).
   * Caller passes true when domain layer already verified assignment.
   */
  assertTechnicianAssigned(snap: TenantContextSnapshot, assigned: boolean): void {
    if (this.isPlatformAdmin(snap)) {
      return;
    }
    if ((snap.activeRole as AppRole) !== 'technician') {
      throw new ForbiddenException('technician_role_required');
    }
    if (!assigned) {
      throw new ForbiddenException('technician_job_scope_denied');
    }
  }
}
