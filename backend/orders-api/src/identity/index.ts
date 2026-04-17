/**
 * Barrel for identity / tenant / RBAC helpers (import paths stay stable for other services).
 */
export { AccessControlService } from './access-control.service';
export { isRbacEnabled, isTenantEnforcementEnabled } from './identity.config';
export { RequirePermissions } from './require-permissions.decorator';
export { RbacGuard } from './rbac.guard';
export { TenantContextGuard } from './tenant-context.guard';
export { TenantContextService } from './tenant-context.service';
export { assertTenantAccess, assertCreateOrderTenantScope, resolveSearchStoreIdForTenant } from './tenant-access';
export { getTenantContext, getGatewayContext, patchGatewayContext } from './tenant-context.storage';
export type { TenantContextSnapshot } from './tenant-context.types';
export type { AppRole } from './rbac-roles.config';
