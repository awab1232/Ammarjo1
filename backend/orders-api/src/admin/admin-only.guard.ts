import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { getTenantContext } from '../identity/tenant-context.storage';

/** Restricts routes to platform operators (`admin` or `system_internal`). */
@Injectable()
export class AdminOnlyGuard implements CanActivate {
  canActivate(_context: ExecutionContext): boolean {
    const snap = getTenantContext();
    const r = snap?.activeRole;
    if (r !== 'admin' && r !== 'system_internal') {
      throw new ForbiddenException('Admin role required');
    }
    return true;
  }
}
