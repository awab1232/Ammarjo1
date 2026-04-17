import { createHmac, timingSafeEqual } from 'crypto';

/**
 * Opaque cursor for keyset pagination on (created_at DESC, order_id DESC).
 *
 * **Signed (v2):** base64url(JSON `{ v, c, o, t, s }`) where `s` = HMAC-SHA256(secret, `v|c|o|t`).
 * **Legacy unsigned:** base64url(JSON `{ c, o }`) — accepted only when `ORDERS_CURSOR_ALLOW_UNSIGNED=1`
 * (or when no `ORDERS_CURSOR_HMAC_SECRET` is configured, for local dev).
 *
 * Env:
 * - `ORDERS_CURSOR_HMAC_SECRET` — required for signing in production (min ~16 chars recommended).
 * - `ORDERS_CURSOR_ALLOW_UNSIGNED` — `1` to accept legacy unsigned cursors during migration (default: off).
 * - `ORDERS_CURSOR_MAX_AGE_MS` — max cursor age for signed cursors (default 7d); `0` = no expiry check.
 */

export type OrderListCursorPayload = { c: string; o: string };

const CURSOR_V2 = 2;
/** Reject absurdly large inputs before base64 decode. */
const MAX_CURSOR_WIRE_CHARS = 512;
/** Cap JSON string length after decode. */
const MAX_JSON_CHARS = 4096;

function cursorSecret(): string | null {
  const s = process.env.ORDERS_CURSOR_HMAC_SECRET?.trim();
  if (!s || s.length < 8) {
    return null;
  }
  return s;
}

function allowUnsignedDecode(): boolean {
  const v = process.env.ORDERS_CURSOR_ALLOW_UNSIGNED?.trim().toLowerCase();
  return v === '1' || v === 'true' || v === 'yes';
}

function maxAgeMs(): number {
  const raw = process.env.ORDERS_CURSOR_MAX_AGE_MS?.trim();
  if (raw === '0') {
    return 0;
  }
  if (raw != null && raw !== '') {
    const n = Number(raw);
    if (Number.isFinite(n) && n >= 0) {
      return n;
    }
  }
  return 7 * 24 * 60 * 60 * 1000;
}

function signPayloadV2(c: string, o: string, t: number, secret: string): string {
  const payload = `${CURSOR_V2}|${c}|${o}|${t}`;
  return createHmac('sha256', secret).update(payload, 'utf8').digest('hex');
}

export function encodeOrderListCursor(createdAt: Date, orderId: string): string {
  const c = createdAt.toISOString();
  const o = orderId.trim();
  const secret = cursorSecret();
  if (secret) {
    const t = Date.now();
    const s = signPayloadV2(c, o, t, secret);
    const obj = { v: CURSOR_V2, c, o, t, s };
    return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64url');
  }
  // Dev / no secret: unsigned (decode still works when secret absent)
  return Buffer.from(JSON.stringify({ c, o }), 'utf8').toString('base64url');
}

/**
 * Decodes and verifies a cursor. Returns `null` for missing input.
 * Invalid signature, tampered payload, or malformed wire format → `null` (caller should 400).
 */
export function decodeOrderListCursor(raw: string | undefined | null): OrderListCursorPayload | null {
  if (raw == null) {
    return null;
  }
  const wire = String(raw).trim();
  if (!wire) {
    return null;
  }
  if (wire.length > MAX_CURSOR_WIRE_CHARS) {
    return null;
  }

  let jsonStr: string;
  try {
    jsonStr = Buffer.from(wire, 'base64url').toString('utf8');
  } catch {
    return null;
  }
  if (jsonStr.length > MAX_JSON_CHARS) {
    return null;
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(jsonStr);
  } catch {
    return null;
  }
  if (parsed == null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return null;
  }

  const p = parsed as Record<string, unknown>;
  const c = p.c != null ? String(p.c).trim() : '';
  const o = p.o != null ? String(p.o).trim() : '';
  if (!c || !o) {
    return null;
  }
  const d = new Date(c);
  if (Number.isNaN(d.getTime())) {
    return null;
  }

  const v = p.v != null ? Number(p.v) : 0;
  const hasSig = typeof p.s === 'string' && /^[0-9a-f]+$/i.test(p.s) && (p.s as string).length >= 32;

  if (v === CURSOR_V2 && hasSig) {
    const secret = cursorSecret();
    if (!secret) {
      return null;
    }
    const t = p.t != null ? Number(p.t) : NaN;
    if (!Number.isFinite(t)) {
      return null;
    }
    const maxAge = maxAgeMs();
    if (maxAge > 0 && Date.now() - t > maxAge) {
      return null;
    }
    const expected = signPayloadV2(c, o, t, secret);
    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(String(p.s).toLowerCase(), 'hex');
    if (a.length !== b.length || !timingSafeEqual(a, b)) {
      return null;
    }
    return { c, o };
  }

  // Legacy unsigned { c, o }
  const noVersion = p.v === undefined || p.v === null;
  if (noVersion && !hasSig && (allowUnsignedDecode() || !cursorSecret())) {
    return { c, o };
  }

  return null;
}
