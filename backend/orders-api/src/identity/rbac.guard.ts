import {
  type CanActivate,
  type ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PERMISSIONS_METADATA_KEY } from './rbac.constants';
import { roleHasPermission } from './rbac-roles.config';
import type { AppRole } from './rbac-roles.config';
import { getTenantContext } from './tenant-context.storage';

@Injectable()
export class RbacGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  private logViolation(
    context: ExecutionContext,
    reason: string,
    details?: Record<string, unknown>,
  ): void {
    const req = context.switchToHttp().getRequest<{ method?: string; route?: { path?: string }; url?: string }>();
    const snap = getTenantContext();
    const routePath = req.route?.path ?? req.url ?? 'unknown';
    const action = req.method ?? 'UNKNOWN';
    console.warn(
      JSON.stringify({
        kind: 'authorization_violation',
        userId: snap?.internalUserId ?? snap?.uid ?? null,
        firebaseUid: snap?.uid ?? null,
        tenantId: snap?.tenantId ?? snap?.storeId ?? snap?.wholesalerId ?? null,
        resource: routePath,
        action,
        endpoint: `${action} ${routePath}`,
        reason,
        ...details,
      }),
    );
  }

  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<{ method?: string }>();
    if (req.method === 'OPTIONS') {
      return true;
    }
    const required = this.reflector.getAllAndOverride<string[]>(PERMISSIONS_METADATA_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (required == null || required.length === 0) {
      return true;
    }

    const snap = getTenantContext();
    if (snap?.uid == null) {
      this.logViolation(context, 'missing_authenticated_principal');
      throw new UnauthorizedException('Authentication required');
    }

    const role = snap.activeRole as AppRole;
    for (const perm of required) {
      if (!roleHasPermission(role, perm)) {
        this.logViolation(context, 'missing_permission', { permission: perm, activeRole: role });
        throw new ForbiddenException(`Missing permission: ${perm}`);
      }
    }
    return true;
  }
}
