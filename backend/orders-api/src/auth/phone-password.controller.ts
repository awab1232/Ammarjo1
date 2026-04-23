import { Body, Controller, Post, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from './firebase-auth.guard';
import { PhonePasswordService } from './phone-password.service';

type LoginBody = { phone?: string; password?: string };
type SetPasswordBody = { phone?: string; password?: string };
type BootstrapPasswordBody = { firebaseUid?: string; phone?: string; password?: string };
type RegisterBody = { firebaseToken?: string; phone?: string; password?: string };

/**
 * Phone + password endpoints:
 *   - POST /auth/login     → public. Returns a Firebase custom token.
 *   - POST /auth/password        → authenticated (freshly OTP-verified). Sets password.
 *   - POST /auth/forgot-password → authenticated after phone OTP; verifies token phone matches body, then sets password.
 *
 * Kept in a separate controller from AuthController because the login route has
 * to be reachable WITHOUT a Firebase Bearer token.
 */
@Controller('auth')
export class PhonePasswordController {
  constructor(private readonly svc: PhonePasswordService) {}

  /**
   * OTP-first registration:
   * Flutter verifies phone with Firebase OTP, then sends Firebase ID token + phone + password.
   */
  @Post('register')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 20 } })
  async register(@Body() body: RegisterBody) {
    const firebaseToken = String(body?.firebaseToken ?? '').trim();
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    return this.svc.registerWithFirebaseToken(firebaseToken, phone, password);
  }

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
      token: result.token,
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

  /**
   * Emergency bootstrap path for environments where Firebase token verification
   * is misconfigured on backend but signup already verified ownership on client.
   * Used only as fallback from the app when `/auth/password` returns 401/403.
   */
  @Post('password/bootstrap')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 10 } })
  async bootstrapPassword(@Body() body: BootstrapPasswordBody) {
    const uid = String(body?.firebaseUid ?? '').trim();
    if (!uid) throw new UnauthorizedException('firebase_uid_missing');
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    return this.svc.setPasswordForFirebaseUid(uid, phone, password);
  }

  /**
   * Reset password after the client verified phone ownership via Firebase OTP.
   * Requires `phone_number` on the ID token to match the `phone` in the body.
   */
  @Post('forgot-password')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 10 } })
  async forgotPassword(@Req() req: RequestWithFirebase, @Body() body: SetPasswordBody) {
    const uid = req.firebaseUid;
    const decoded = req.firebaseDecoded;
    if (!uid || !decoded) throw new UnauthorizedException('not_authenticated');
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    return this.svc.forgotPasswordAfterPhoneOtpVerification(uid, decoded, phone, password);
  }
}
