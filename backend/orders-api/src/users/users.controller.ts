import {
  BadRequestException,
  Body,
  Controller,
  ForbiddenException,
  Get,
  Logger,
  NotFoundException,
  Param,
  Patch,
  Post,
  Req,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { getTenantContext } from '../identity/tenant-context.storage';
import { normalizeDbRoleToAppRole } from '../identity/db-user-role.util';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { UserLocationDto } from './dto/user-location.dto';
import { UsersService } from './users.service';

@Controller()
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(private readonly users: UsersService) {}

  /**
   * Self profile — same document shape the Flutter `BackendUserClient` / Firestore `users/{uid}` expected.
   * `:id` must be the signed-in user’s Firebase UID.
   */
  @Get('users/:id')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('orders.read')
  async getUserByFirebaseUid(@Req() req: RequestWithFirebase, @Param('id') id: string) {
    const target = (id || '').trim();
    if (target === 'location') {
      throw new NotFoundException();
    }
    if (!req.firebaseUid) {
      throw new UnauthorizedException('Not authenticated');
    }
    if (target !== req.firebaseUid) {
      throw new ForbiddenException();
    }
    const snap = getTenantContext();
    if (!snap?.uid || snap.uid !== target) {
      throw new ForbiddenException();
    }
    const found = await this.users.findProfileRowByFirebaseUid(target);
    if (!found) {
      throw new NotFoundException('user not found');
    }
    const { row, phone, profile, banned } = found;
    const role = normalizeDbRoleToAppRole(row.role);
    const internalId =
      snap.internalUserId != null && String(snap.internalUserId).trim() !== ''
        ? String(snap.internalUserId).trim()
        : String(row.id);
    const loyalty = Math.max(0, Math.floor(Number(profile['loyaltyPoints'] ?? 0)));
    return {
      id: internalId,
      userId: snap.internalUserId ?? String(row.id),
      role,
      storeId: snap.storeId ?? undefined,
      storeType: snap.storeType ?? undefined,
      firebaseUid: row.firebase_uid,
      email: row.email ?? (profile['email'] != null ? String(profile['email']) : null),
      phone: phone ?? (profile['phone'] != null ? String(profile['phone']) : null),
      name: profile['name'] != null ? String(profile['name']) : null,
      firstName: profile['firstName'] != null ? String(profile['firstName']) : null,
      lastName: profile['lastName'] != null ? String(profile['lastName']) : null,
      addressLine: profile['addressLine'] != null ? String(profile['addressLine']) : null,
      city: profile['city'] != null ? String(profile['city']) : null,
      country: (profile['country'] != null ? String(profile['country']) : 'JO') || 'JO',
      contactEmail: profile['contactEmail'] != null ? String(profile['contactEmail']) : null,
      loyaltyPoints: loyalty,
      banned,
      tenantId: snap.tenantId,
      wholesalerId: snap.wholesalerId,
      permissions: [...snap.permissions],
    };
  }

  @Patch('users/:id')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 60 } })
  @RequirePermissions('orders.write')
  async patchUser(
    @Req() req: RequestWithFirebase,
    @Param('id') id: string,
    @Body() body: unknown,
  ) {
    const target = (id || '').trim();
    if (!req.firebaseUid) {
      throw new UnauthorizedException();
    }
    if (target !== req.firebaseUid) {
      throw new ForbiddenException();
    }
    if (body == null || typeof body !== 'object' || Array.isArray(body)) {
      throw new BadRequestException();
    }
    await this.users.patchUserProfile(target, body as Record<string, unknown>);
    return { ok: true as const };
  }

  /**
   * Persists last known map position for delivery coordinate fallback (migration 032+).
   */
  @Post('users/location')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard, RbacGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 120 } })
  @RequirePermissions('orders.read')
  async updateLocation(@Req() req: RequestWithFirebase, @Body() raw: unknown) {
    const dto = plainToInstance(UserLocationDto, raw ?? {}, { enableImplicitConversion: true });
    const errors = await validate(dto);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    const uid = req.firebaseUid!;
    const ok = await this.users.updateLastKnownLocation(uid, dto.lat, dto.lng);
    if (!ok) {
      this.logger.warn(JSON.stringify({ kind: 'user_location_update_skipped', userId: uid }));
      return { ok: false, reason: 'not_persisted' };
    }
    this.logger.log(JSON.stringify({ kind: 'user_location_updated', userId: uid }));
    return { ok: true };
  }
}
