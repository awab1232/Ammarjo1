import { ForbiddenException } from '@nestjs/common';
import { isTenantEnforcementEnabled } from './identity.config';
import { getTenantContext } from './tenant-context.storage';

function logTenantViolation(reason: string): void {
  const ctx = getTenantContext();
  console.warn(
    JSON.stringify({
      kind: 'tenant_violation',
      userId: ctx?.uid ?? null,
      tenantId: ctx?.tenantId ?? ctx?.storeId ?? ctx?.wholesalerId ?? null,
      endpoint: 'unknown',
      reason,
    }),
  );
}

/**
 * Assert resource belongs to the caller's tenant scope (when enforcement is on).
 * Admins / system_internal bypass.
 */
export function assertTenantAccess(resource: {
  resourceUserId?: string | null;
  storeId?: string | null;
  wholesalerId?: string | null;
}): void {
  if (!isTenantEnforcementEnabled()) {
    return;
  }
  const ctx = getTenantContext();
  if (!ctx?.uid) {
    return;
  }
  if (ctx.activeRole === 'admin' || ctx.activeRole === 'system_internal') {
    return;
  }

  if (resource.resourceUserId != null && String(resource.resourceUserId) !== String(ctx.uid)) {
    logTenantViolation('user_scope_violation');
    throw new ForbiddenException('User scope violation');
  }

  if (ctx.activeRole === 'store_owner' && ctx.storeId != null) {
    if (
      resource.storeId != null &&
      String(resource.storeId).length > 0 &&
      String(resource.storeId) !== String(ctx.storeId)
    ) {
      logTenantViolation('store_scope_violation');
      throw new ForbiddenException('Store scope violation');
    }
  }

  const isWholesaleStoreOwner =
    ctx.activeRole === 'store_owner' && String(ctx.storeType ?? '').trim().toLowerCase() === 'wholesale';
  if ((String(ctx.activeRole) === 'wholesaler_owner' || isWholesaleStoreOwner) && ctx.wholesalerId != null) {
    if (
      resource.wholesalerId != null &&
      String(resource.wholesalerId).length > 0 &&
      String(resource.wholesalerId) !== String(ctx.wholesalerId)
    ) {
      logTenantViolation('wholesaler_scope_violation');
      throw new ForbiddenException('Wholesaler scope violation');
    }
  }
}

/** POST /orders — restrict store target for store_owner when enforcement is on. */
export function assertCreateOrderTenantScope(
  firebaseUid: string,
  orderStoreId: string | undefined,
): void {
  if (!isTenantEnforcementEnabled()) {
    return;
  }
  const ctx = getTenantContext();
  if (!ctx?.uid) {
    return;
  }
  if (ctx.activeRole === 'admin' || ctx.activeRole === 'system_internal') {
    return;
  }
  if (ctx.activeRole === 'store_owner' && ctx.storeId) {
    const sid = orderStoreId != null ? String(orderStoreId).trim() : '';
    if (!sid || sid !== String(ctx.storeId)) {
      logTenantViolation('create_order_store_scope_violation');
      throw new ForbiddenException('Orders must target your store');
    }
  }
}

/**
 * Algolia store filter: when enforcement is on and caller is a scoped store_owner,
 * force / validate storeId facet.
 */
export function resolveSearchStoreIdForTenant(queryStoreId: string | undefined): string | undefined {
  if (!isTenantEnforcementEnabled()) {
    return queryStoreId?.trim() || undefined;
  }
  const ctx = getTenantContext();
  if (!ctx?.uid) {
    return queryStoreId?.trim() || undefined;
  }
  if (ctx.activeRole === 'admin' || ctx.activeRole === 'system_internal') {
    return queryStoreId?.trim() || undefined;
  }
  if (ctx.activeRole === 'store_owner' && ctx.storeId) {
    const q = queryStoreId?.trim();
    if (q && q !== String(ctx.storeId)) {
      logTenantViolation('search_store_filter_scope_violation');
      throw new ForbiddenException('Store filter must match your tenant');
    }
    return String(ctx.storeId);
  }
  return queryStoreId?.trim() || undefined;
}

/**
 * Wholesale layer visibility by store_type:
 * - construction_store: allowed
 * - home_store / others: denied
 */
export function assertWholesaleStoreTypeAccess(): void {
  if (!isTenantEnforcementEnabled()) {
    return;
  }
  const ctx = getTenantContext();
  if (!ctx?.uid) {
    return;
  }
  if (ctx.activeRole === 'admin' || ctx.activeRole === 'system_internal') {
    return;
  }
  if (ctx.activeRole !== 'store_owner') {
    logTenantViolation('wholesale_non_store_owner');
    throw new ForbiddenException('Wholesale endpoints are only available for store owners');
  }
  if ((ctx.storeType ?? '').trim().toLowerCase() !== 'construction_store') {
    logTenantViolation('wholesale_store_type_violation');
    throw new ForbiddenException('Wholesale endpoints are limited to construction_store');
  }
}
