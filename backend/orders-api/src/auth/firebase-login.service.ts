import { Injectable, UnauthorizedException } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import { getFirebaseAuth } from './firebase-admin';
import { signBackendSessionToken } from './session-token.util';

@Injectable()
export class FirebaseLoginService {
  constructor(private readonly users: UsersService) {}

  async loginWithFirebaseIdToken(idToken: string) {
    const token = idToken.trim();
    if (!token) throw new UnauthorizedException('Missing Firebase ID token');
    let decoded;
    try {
      decoded = await getFirebaseAuth().verifyIdToken(token);
      console.log('[AUTH-AUDIT] Decoded UID:', decoded.uid);
      console.log('[AUTH-AUDIT] Decoded email:', decoded.email);
    } catch {
      console.log('[AUTH-AUDIT] verifyIdToken failed');
      throw new UnauthorizedException('Invalid or expired Firebase ID token');
    }

    const user = await this.users.ensureUser(decoded);
    console.log('[AUTH-AUDIT] User in DB:', {
      id: user.id,
      firebase_uid: user.firebase_uid,
      email: user.email,
      role: user.role,
      tenant_id: user.tenant_id,
    });
    const sessionToken = signBackendSessionToken({
      uid: user.firebase_uid,
      userId: user.id,
      role: user.role,
    });
    console.log('[AUTH-AUDIT] Session token length:', sessionToken.length);

    return {
      user: {
        id: user.id,
        firebaseUid: user.firebase_uid,
        email: user.email,
        role: user.role,
        storeId: user.store_id,
        storeType: user.store_type,
        tenantId: user.tenant_id,
        wholesalerId: user.wholesaler_id,
      },
      token: sessionToken,
      authType: 'firebase_id_token',
    };
  }
}
