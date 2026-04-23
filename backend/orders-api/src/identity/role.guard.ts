import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { getTenantContext } from './tenant-context.storage';
import { ROLE_GUARD_KEY } from './roles.decorator';

@Injectable()
export class RoleGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const allowed = this.reflector.getAllAndOverride<string[]>(ROLE_GUARD_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!allowed || allowed.length == 0) return true;

    const snap = getTenantContext();
    const role = String(snap?.activeRole ?? snap?.persistedRole ?? 'customer').trim().toLowerCase();
    const ok = allowed.includes(role);
    if (!ok) {
      throw new ForbiddenException('missing_permission');
    }
    return true;
  }
}

