import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { getTenantContext } from '../identity/tenant-context.storage';
import { isValidPersistedRole, normalizeDbRoleToAppRole } from '../identity/db-user-role.util';
import { UsersService } from '../users/users.service';
import { FirebaseAuthGuard, type RequestWithFirebase } from './firebase-auth.guard';
import { SessionsService } from './sessions.service';

function apiRoleFromPersisted(role: string | null | undefined): string {
  return normalizeDbRoleToAppRole(role);
}

/** Canonical role string for clients (`GET /auth/me`). */
function apiMeRole(role: string): string {
  return normalizeDbRoleToAppRole(role);
}

@Controller('auth')
@UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
@ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
export class AuthController {
  constructor(
    private readonly users: UsersService,
    private readonly sessions: SessionsService,
  ) {}

  @Get('me')
  async me(@Req() req: RequestWithFirebase) {
    const snap = getTenantContext();
    if (!req.firebaseUid) {
      throw new UnauthorizedException('Not authenticated');
    }
    if (!snap?.uid) {
      throw new UnauthorizedException('tenant context unavailable');
    }
    const persisted = apiRoleFromPersisted(snap.persistedRole);
    const role = apiMeRole(persisted);
    const id = (snap.internalUserId != null && String(snap.internalUserId).trim() !== ''
      ? String(snap.internalUserId).trim()
      : snap.uid) as string;
    return {
      id,
      role,
      storeId: snap.storeId ?? undefined,
      storeType: snap.storeType ?? undefined,
      userId: snap.internalUserId,
      firebaseUid: snap.uid,
      email: snap.email,
      tenantId: snap.tenantId,
      wholesalerId: snap.wholesalerId,
      permissions: [...snap.permissions],
    };
  }

  @Post('set-role')
  @RequirePermissions('*')
  async setRole(
    @Req() req: RequestWithFirebase,
    @Body()
    body: {
      firebaseUid: string;
      role: string;
      tenantId?: string | null;
      storeId?: string | null;
      storeType?: string | null;
    },
  ) {
    const role = String(body?.role ?? '').trim().toLowerCase();
    if (!isValidPersistedRole(role)) {
      throw new ForbiddenException('invalid_role');
    }
    const targetUid = String(body?.firebaseUid ?? '').trim();
    if (!targetUid) {
      throw new ForbiddenException('firebaseUid required');
    }
    const tenantId = body.tenantId != null && String(body.tenantId).trim() ? String(body.tenantId).trim() : null;
    const storeId = body.storeId != null && String(body.storeId).trim() ? String(body.storeId).trim() : null;
    const storeType = body.storeType != null && String(body.storeType).trim() ? String(body.storeType).trim() : null;

    const updated = await this.users.updateRoleByFirebaseUid(
      targetUid,
      role,
      tenantId,
      storeId,
      storeType,
    );
    if (!updated) {
      throw new ForbiddenException('user_not_found');
    }
    return { ok: true, user: updated };
  }

  /** Register / refresh the current device session. Called on each app startup or login. */
  @Post('session')
  @RequirePermissions('orders.read')
  async registerSession(
    @Req() req: RequestWithFirebase,
    @Body()
    body: {
      deviceId?: string;
      deviceName?: string;
      deviceOs?: string;
      appVersion?: string;
    },
  ) {
    const uid = req.firebaseUid;
    if (!uid) throw new UnauthorizedException('Not authenticated');
    const deviceId = String(body?.deviceId ?? '').trim();
    if (!deviceId) throw new ForbiddenException('deviceId required');

    const ip =
      (req.headers['x-forwarded-for'] as string | undefined)?.split(',')[0]?.trim() ??
      (req as unknown as { ip?: string }).ip ??
      null;

    const session = await this.sessions.upsertSession({
      firebaseUid: uid,
      deviceId,
      deviceName: String(body?.deviceName ?? '').trim() || 'Unknown Device',
      deviceOs: String(body?.deviceOs ?? '').trim() || 'Unknown OS',
      appVersion: String(body?.appVersion ?? '').trim() || '0.0.0',
      ipAddress: ip,
    });
    return { ok: true, session };
  }

  /** List sessions for the currently signed-in user. */
  @Get('sessions')
  @RequirePermissions('orders.read')
  async mySessions(@Req() req: RequestWithFirebase) {
    const uid = req.firebaseUid;
    if (!uid) throw new UnauthorizedException('Not authenticated');
    const rows = await this.sessions.listForUser(uid);
    return { sessions: rows };
  }
}
