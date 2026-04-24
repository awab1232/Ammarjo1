import { BadRequestException, Body, Controller, Post, Req, UnauthorizedException, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { ApiPolicy } from '../gateway/api-policy.decorator';
import { ApiPolicyGuard } from '../gateway/api-policy.guard';
import { TenantContextGuard } from '../identity/tenant-context.guard';
import { FirebaseAuthGuard, type RequestWithFirebase } from './firebase-auth.guard';
import { PhonePasswordService } from './phone-password.service';

type LoginBody = { phone?: string; password?: string };
type SetPasswordBody = { phone?: string; password?: string };
type BootstrapPasswordBody = { firebaseUid?: string; phone?: string; password?: string };
type RegisterBody = { firebaseToken?: string; phone?: string; password?: string };
type RequestWithHeaders = Request & { headers: Request['headers'] };

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
  async register(@Req() req: RequestWithHeaders, @Body() body: RegisterBody) {
    console.log('REGISTER HIT');
    console.log('🔥 /auth/register HIT');
    const firebaseTokenFromBody = String(body?.firebaseToken ?? '').trim();
    const authHeader = req.headers.authorization;
    const firebaseTokenFromHeader =
      typeof authHeader === 'string' && authHeader.startsWith('Bearer ')
        ? authHeader.slice('Bearer '.length).trim()
        : '';
    const firebaseToken = firebaseTokenFromHeader.length > 0 ? firebaseTokenFromHeader : firebaseTokenFromBody;
    const phone = String(body?.phone ?? '').trim();
    const password = String(body?.password ?? '');
    console.log('🔥 phone:', phone);
    return this.svc.registerWithFirebaseToken(firebaseToken, phone, password);
  }

  /** Disabled in strict mode: only Firebase ID token auth is allowed. */
  @Post('login')
  @UseGuards(TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: false, tenant: 'optional', rateLimit: { rpm: 30 } })
  async login(@Body() _body: LoginBody) {
    throw new BadRequestException('PHONE_PASSWORD_DISABLED_USE_FIREBASE');
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

  /** Disabled in strict mode: no fallback auth paths are allowed. */
  @Post('password/bootstrap')
  @UseGuards(FirebaseAuthGuard, TenantContextGuard, ApiPolicyGuard)
  @ApiPolicy({ auth: true, tenant: 'optional', rateLimit: { rpm: 10 } })
  async bootstrapPassword(@Req() _req: RequestWithFirebase, @Body() _body: BootstrapPasswordBody) {
    throw new BadRequestException('PHONE_PASSWORD_DISABLED_USE_FIREBASE');
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
