import type { Request } from 'express';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { permissionsForRole } from './rbac-roles.config';
import { emptyTenantContextSnapshot, type TenantContextSnapshot } from './tenant-context.types';

function headerTraceId(req: Request): string | null {
  const a = req.headers['x-request-id'];
  const b = req.headers['x-trace-id'];
  const c = req.headers['traceparent'];
  const v = (typeof a === 'string' && a.trim()) || (typeof b === 'string' && b.trim()) || '';
  if (v) {
    return v;
  }
  if (typeof c === 'string' && c.trim()) {
    const parts = c.trim().split('-');
    if (parts.length >= 2 && parts[1]) {
      return parts[1];
    }
  }
  return null;
}

function pickCustomClaims(decoded: DecodedIdToken): Record<string, unknown> {
  const d = decoded as Record<string, unknown>;
  const keys = [
    'role',
    'roles',
    'storeId',
    'storeType',
    'store_type',
    'tenantId',
    'wholesalerId',
    'admin',
    'activeRole',
  ];
  const out: Record<string, unknown> = {};
  for (const k of keys) {
    if (k in d) {
      out[k] = d[k];
    }
  }
  return out;
}

/**
 * Identity-only slice from Firebase ID token. RBAC activeRole comes from PostgreSQL `users` (see UsersService.mergeSnapshotWithUser); claims stay in customClaims for audit only.
 */
export function buildTenantSnapshotFromRequest(
  req: Request,
  decoded: DecodedIdToken | undefined,
): TenantContextSnapshot {
  const base = emptyTenantContextSnapshot();
  base.requestTraceId = headerTraceId(req);

  if (!decoded) {
    return base;
  }

  base.uid = decoded.uid ?? null;
  base.email = decoded.email != null ? String(decoded.email) : null;
  base.customClaims = pickCustomClaims(decoded);
  base.roles = [];
  base.activeRole = 'customer';
  base.permissions = [...permissionsForRole('customer')];
  base.internalUserId = null;
  base.persistedRole = null;

  return base;
}
