import { Body, Controller, Post, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from './firebase-auth.guard';
import { PhonePasswordService } from './phone-password.service';

type LoginBody = { phone?: string; password?: string };
type SetPasswordBody = { phone?: string; password?: string };

/**
 * Phone + password endpoints:
 *   - POST /auth/login     → public. Returns a Firebase custom token.
 *   - POST /auth/password  → authenticated (freshly OTP-verified). Sets password.
 *
 * Kept in a separate controller from AuthController because the login route has
 * to be reachable WITHOUT a Firebase Bearer token.
 */
@Controller('auth')
export class PhonePasswordController {
  constructor(private readonly svc: PhonePasswordService) {}

  /** Public phone + password login — issues a Firebase custom token. */
  @Post('login')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 30 } })
  async login(@Body() body: LoginBody) {
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    const result = await this.svc.loginWithPhonePassword(phone, password);
    return {
      ok: true,
      customToken: result.customToken,
      firebaseUid: result.firebaseUid,
      phone: result.phone,
    };
  }

  /**
   * Authenticated — call this from the signup flow right after Firebase has
   * verified the OTP. The Bearer token is the fresh Firebase ID token.
   */
  @Post('password')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 20 } })
  async setPassword(@Req() req: RequestWithFirebase, @Body() body: SetPasswordBody) {
    const uid = req.firebaseUid;
    if (!uid) throw new UnauthorizedException('not_authenticated');
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    return this.svc.setPasswordForFirebaseUid(uid, phone, password);
  }
}
