import { createHmac, timingSafeEqual } from 'crypto';

export type BackendSessionPayload = {
  uid: string;
  userId: string;
  role: string;
  iat: number;
  exp: number;
};

export function signBackendSessionToken(payload: {
  uid: string;
  userId: string;
  role: string;
}): string {
  const secret = sessionSecret();
  const body = JSON.stringify({
    uid: payload.uid,
    userId: payload.userId,
    role: payload.role,
    iat: Date.now(),
    exp: Date.now() + sessionTtlMs(),
  });
  const base = Buffer.from(body, 'utf8').toString('base64url');
  const sig = createHmac('sha256', secret).update(base).digest('base64url');
  return `sess_${base}.${sig}`;
}

export function verifyBackendSessionToken(token: string): BackendSessionPayload | null {
  const secret = sessionSecretOrNull();
  if (secret == null) return null;
  if (!token.startsWith('sess_')) return null;
  const bodyAndSig = token.slice('sess_'.length);
  const parts = bodyAndSig.split('.');
  if (parts.length != 2) return null;
  const [base, gotSig] = parts;
  if (!base || !gotSig) return null;
  const expectedSig = createHmac('sha256', secret).update(base).digest('base64url');
  const gotBuf = Buffer.from(gotSig, 'utf8');
  const expBuf = Buffer.from(expectedSig, 'utf8');
  if (gotBuf.length !== expBuf.length) return null;
  if (!timingSafeEqual(gotBuf, expBuf)) return null;
  try {
    const payload = JSON.parse(Buffer.from(base, 'base64url').toString('utf8')) as BackendSessionPayload;
    if (!payload.uid || !payload.userId) return null;
    if (!Number.isFinite(payload.exp) || payload.exp <= Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}

function sessionSecret(): string {
  const secret = sessionSecretOrNull();
  if (secret == null) {
    throw new Error('AUTH_SESSION_SECRET or INTERNAL_API_KEY must be configured');
  }
  return secret;
}

function sessionSecretOrNull(): string | null {
  const secret = (process.env.AUTH_SESSION_SECRET ?? process.env.INTERNAL_API_KEY ?? '').trim();
  return secret.length > 0 ? secret : null;
}

function sessionTtlMs(): number {
  const raw = Number(process.env.AUTH_SESSION_TTL_MS ?? 24 * 60 * 60 * 1000);
  if (!Number.isFinite(raw) || raw <= 0) {
    return 24 * 60 * 60 * 1000;
  }
  return raw;
}
