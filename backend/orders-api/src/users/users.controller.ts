import { BadRequestException, Body, Controller, Logger, Post, Req, UseGuards } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { RbacGuard } from '../identity/rbac.guard';
import { RequirePermissions } from '../identity/require-permissions.decorator';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from '../auth/firebase-auth.guard';
import { UserLocationDto } from './dto/user-location.dto';
import { UsersService } from './users.service';

@Controller()
export class UsersController {
  private readonly logger = new Logger(UsersController.name);

  constructor(private readonly users: UsersService) {}

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
