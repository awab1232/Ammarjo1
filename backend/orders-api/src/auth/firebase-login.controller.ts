import { Controller, Post, Req, UnauthorizedException } from '@nestjs/common';
import type { Request } from 'express';
import { FirebaseLoginService } from './firebase-login.service';

type RequestWithAuth = Request & { headers: Request['headers'] };

@Controller('auth')
export class FirebaseLoginController {
  constructor(private readonly firebaseLogin: FirebaseLoginService) {}

  @Post('firebase-login')
  async loginWithFirebase(@Req() req: RequestWithAuth) {
    const authHeader = req.headers.authorization;
    console.log('[AUTH-AUDIT] Authorization header present:', Boolean(authHeader));
    console.log(
      '[AUTH-AUDIT] Authorization startsWith Bearer:',
      typeof authHeader === 'string' ? authHeader.startsWith('Bearer ') : false,
    );
    const token = extractBearerToken(req.headers.authorization);
    if (token == null) {
      console.log('[AUTH-AUDIT] Token extracted: null/empty');
      throw new UnauthorizedException('Missing or invalid Authorization header');
    }
    console.log('[AUTH-AUDIT] Received token length:', token.length);
    return this.firebaseLogin.loginWithFirebaseIdToken(token);
  }
}

function extractBearerToken(header: string | string[] | undefined): string | null {
  const raw = Array.isArray(header) ? header[0] : header;
  if (!raw || !raw.startsWith('Bearer ')) return null;
  const token = raw.slice('Bearer '.length).trim();
  return token.length > 0 ? token : null;
}

