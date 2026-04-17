/**
 * Role → permission strings (config-only; DB overrides in a later phase).
 * RBAC is always enforced; these define the default permission matrix.
 */

export type AppRole =
  | 'admin'
  | 'store_owner'
  | 'technician'
  | 'customer'
  | 'system_internal';

/** Wildcard grants every permission check. */
export const PERMISSION_WILDCARD = '*';

export const ALL_KNOWN_PERMISSIONS: string[] = [
  'orders.read',
  'orders.write',
  'stores.manage',
  'products.manage',
  'events.read',
  'dlq.manage',
];

export const ROLE_PERMISSIONS: Record<AppRole, readonly string[]> = {
  admin: [PERMISSION_WILDCARD],
  system_internal: [PERMISSION_WILDCARD],
  store_owner: [
    'orders.read',
    'orders.write',
    'stores.manage',
    'products.manage',
    'events.read',
  ],
  technician: ['orders.read', 'events.read'],
  customer: ['orders.read', 'orders.write', 'events.read'],
};

export function permissionsForRole(role: AppRole): readonly string[] {
  return ROLE_PERMISSIONS[role] ?? ROLE_PERMISSIONS.customer;
}

export function roleHasPermission(role: AppRole, permission: string): boolean {
  const perms = permissionsForRole(role);
  if (perms.includes(PERMISSION_WILDCARD)) {
    return true;
  }
  return perms.includes(permission);
}
