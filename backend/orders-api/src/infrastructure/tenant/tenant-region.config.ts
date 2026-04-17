/** When "1", tenant preferred region (in-memory map) may override gateway resolution. */
export function isTenantRegionEnforcementEnabled(): boolean {
  return process.env.TENANT_REGION_ENFORCEMENT?.trim() === '1';
}
