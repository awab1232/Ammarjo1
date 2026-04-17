/**
 * RBAC and tenant rules are always enforced in application code (no env bypass).
 * @deprecated Kept for compatibility; always true.
 */

export function isRbacEnabled(): boolean {
  return true;
}

export function isTenantEnforcementEnabled(): boolean {
  return true;
}
