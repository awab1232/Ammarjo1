import type { AppRole } from './rbac-roles.config';

/**
 * Request-scoped identity + tenant slice (ALS-backed).
 * Populated from Firebase ID token + optional headers.
 */
export type TenantContextSnapshot = {
  uid: string | null;
  email: string | null;
  /** Primary key of `users` row when provisioned (backend RBAC). */
  internalUserId: string | null;
  /** Persisted role string from `users.role` (audit / /auth/me). */
  persistedRole: string | null;
  /** Raw role strings from token claims (if any). */
  roles: string[];
  activeRole: AppRole;
  /** Subset of Firebase custom claims useful for auditing (not the full token). */
  customClaims: Record<string, unknown>;
  /** Primary tenant id (often same as storeId or wholesalerId). */
  tenantId: string | null;
  storeId: string | null;
  storeType: string | null;
  wholesalerId: string | null;
  /** Effective permission strings for activeRole. */
  permissions: readonly string[];
  /** Correlates with HTTP / outbox tracing (headers first). */
  requestTraceId: string | null;
};

export function emptyTenantContextSnapshot(): TenantContextSnapshot {
  return {
    uid: null,
    email: null,
    internalUserId: null,
    persistedRole: null,
    roles: [],
    activeRole: 'customer',
    customClaims: {},
    tenantId: null,
    storeId: null,
    storeType: null,
    wholesalerId: null,
    permissions: [],
    requestTraceId: null,
  };
}
