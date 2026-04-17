import type { AppRole } from './rbac-roles.config';

/**
 * Map persisted DB role string → AppRole. Unknown values default to customer.
 */
export function normalizeDbRoleToAppRole(raw: string | null | undefined): AppRole {
  const r = String(raw ?? '')
    .trim()
    .toLowerCase();
  if (!r) return 'customer';
  switch (r) {
    case 'admin':
      return 'admin';
    case 'system_internal':
      return 'system_internal';
    case 'store_owner':
    case 'wholesaler':
    case 'wholesaler_owner':
      return 'store_owner';
    case 'technician':
      return 'technician';
    case 'customer':
    default:
      return 'customer';
  }
}

export function isValidPersistedRole(raw: string): boolean {
  const r = raw.trim().toLowerCase();
  return (
    r === 'admin' ||
    r === 'store_owner' ||
    r === 'technician' ||
    r === 'customer' ||
    r === 'system_internal'
  );
}
