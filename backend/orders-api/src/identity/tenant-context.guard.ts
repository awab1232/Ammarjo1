import {
  type CanActivate,
  type ExecutionContext,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import type { Request } from 'express';
import {
  GlobalRegionContextService,
  type GlobalCountryCode,
} from '../architecture/global-region-context.service';
import { getFirebaseAuth } from '../auth/firebase-admin';
import type { RequestWithFirebase } from '../auth/firebase-auth.guard';
import { UsersService } from '../users/users.service';
import { buildTenantSnapshotFromRequest } from './build-tenant-snapshot';
import {
  isMultiRegionRoutingEnabled,
  normalizeCountryCode,
} from '../infrastructure/routing/routing.config';
import { getTenantContext, setTenantContextSnapshot } from './tenant-context.storage';

/**
 * Runs **after** [FirebaseAuthGuard] when present: builds ALS tenant snapshot for RBAC / tenant checks.
 * On unauthenticated routes, optionally verifies Bearer (when tenant enforcement is on) so search can scope by tenant.
 */
@Injectable()
export class TenantContextGuard implements CanActivate {
  constructor(
    private readonly globalRegion: GlobalRegionContextService,
    private readonly users: UsersService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<RequestWithFirebase & Request>();
    await this.hydrateOptionalFirebase(req);
    let snap = buildTenantSnapshotFromRequest(req, req.firebaseDecoded);
    if (req.firebaseDecoded) {
      try {
        const row = await this.users.ensureUser(req.firebaseDecoded);
        snap = this.users.mergeSnapshotWithUser(snap, row, req.firebaseDecoded);
      } catch (e) {
        if (e instanceof ServiceUnavailableException) {
          throw e;
        }
        throw new ServiceUnavailableException('user profile load failed');
      }
    }
    setTenantContextSnapshot(snap);
    if (isMultiRegionRoutingEnabled()) {
      const snap = getTenantContext();
      const patch: {
        tenantId?: string;
        country?: GlobalCountryCode;
        region?: string;
      } = { tenantId: snap?.tenantId ?? undefined };
      const fromClaim = snap?.customClaims?.['country'];
      if (typeof fromClaim === 'string') {
        const c = normalizeCountryCode(fromClaim);
        if (c !== 'UNKNOWN') {
          patch.country = c;
          patch.region = c === 'EG' ? 'EG' : 'JO';
        }
      }
      this.globalRegion.patch(patch);
    }
    return true;
  }

  private async hydrateOptionalFirebase(req: RequestWithFirebase): Promise<void> {
    if (req.firebaseDecoded) {
      return;
    }
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return;
    }
    // Verify Bearer early so global RbacGuard runs after DB-backed [activeRole] (same order as route-level FirebaseAuthGuard).
    // Security: never log the Bearer token or Authorization header.
    const token = header.slice('Bearer '.length).trim();
    if (!token) {
      return;
    }
    try {
      const decoded = await getFirebaseAuth().verifyIdToken(token);
      req.firebaseUid = decoded.uid;
      req.firebaseDecoded = decoded;
    } catch {
      /* leave unauthenticated */
    }
  }
}
