import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request } from 'express';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { logAuditJson } from '../common/audit-log';
import { getFirebaseAuth } from './firebase-admin';
import { getTenantContext } from '../identity/tenant-context.storage';

export type RequestWithFirebase = Request & {
  firebaseUid?: string;
  firebaseDecoded?: DecodedIdToken;
};

@Injectable()
export class FirebaseAuthGuard implements CanActivate {
  private logAuthFailure(context: ExecutionContext, reason: string): void {
    const req = context.switchToHttp().getRequest<Request>();
    const snap = getTenantContext();
    logAuditJson('login_attempt', {
      result: 'failure',
      reason,
      endpoint: `${req.method} ${req.route?.path ?? req.url}`,
      userId: snap?.uid ?? null,
      tenantId: snap?.tenantId ?? snap?.storeId ?? snap?.wholesalerId ?? null,
    });
  }

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const req = context.switchToHttp().getRequest<RequestWithFirebase>();
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      this.logAuthFailure(context, 'missing_or_invalid_authorization_header');
      throw new UnauthorizedException('Missing or invalid Authorization header');
    }
    const token = header.slice('Bearer '.length).trim();
    if (!token) {
      this.logAuthFailure(context, 'empty_bearer_token');
      throw new UnauthorizedException('Empty bearer token');
    }
    try {
      const auth = getFirebaseAuth();
      const decoded = await auth.verifyIdToken(token);
      req.firebaseUid = decoded.uid;
      req.firebaseDecoded = decoded;
      return true;
    } catch {
      this.logAuthFailure(context, 'invalid_or_expired_firebase_id_token');
      throw new UnauthorizedException('Invalid or expired Firebase ID token');
    }
  }
}
