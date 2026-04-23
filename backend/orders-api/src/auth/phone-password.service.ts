import {
  BadRequestException,
  Injectable,
  Logger,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { Pool, type PoolClient } from 'pg';
import type { DecodedIdToken } from 'firebase-admin/auth';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';
import { getFirebaseAuth } from './firebase-admin';
import { signBackendSessionToken } from './session-token.util';

const MIN_PASSWORD_LEN = 6;
const MAX_PASSWORD_LEN = 128;
const BCRYPT_ROUNDS = Number(process.env.PHONE_PASSWORD_BCRYPT_ROUNDS || 10);

/**
 * Persists phone + bcrypt(password) on the `users` row and issues Firebase
 * custom tokens when a caller logs in with phone + password. OTP remains the
 * proof-of-phone-ownership step at signup time — this service is only reached
 * AFTER Firebase has already verified the phone number, or later when the
 * caller wants to exchange a (phone, password) pair for a fresh custom token.
 */
@Injectable()
export class PhonePasswordService {
  private readonly logger = new Logger(PhonePasswordService.name);
  private readonly pool: Pool | null;
  private schemaReady = false;
  private schemaPromise: Promise<void> | null = null;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: Number(process.env.AUTH_PG_POOL_MAX || 4),
            idleTimeoutMillis: 30_000,
          }),
        )
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) {
      throw new ServiceUnavailableException('auth database not configured');
    }
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      return await fn(client);
    } finally {
      client.release();
    }
  }

  /**
   * Lazy, idempotent schema guard — runs the ALTER TABLE statements from
   * `sql/migrations/027_add_phone_password_to_users.sql` on first use so the
   * endpoint keeps working even if the operator forgot to apply the migration.
   */
  private async ensureSchema(): Promise<void> {
    if (this.schemaReady) return;
    if (!this.schemaPromise) {
      this.schemaPromise = this.withClient(async (client) => {
        await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT`);
        await client.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash TEXT`);
        await client.query(
          `ALTER TABLE users ADD COLUMN IF NOT EXISTS password_updated_at TIMESTAMPTZ`,
        );
        await client.query(
          `CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone) WHERE phone IS NOT NULL`,
        );
        await client.query(
          `CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_non_empty
           ON users ((NULLIF(btrim(phone), '')))
           WHERE phone IS NOT NULL AND btrim(phone) <> ''`,
        );
        this.schemaReady = true;
      }).catch((err) => {
        this.schemaPromise = null;
        throw err;
      });
    }
    return this.schemaPromise;
  }

  /** Normalise local/JO input to E.164 — accepts 07XXXXXXXX, 7XXXXXXXX, +9627XXXXXXXX, 9627XXXXXXXX. */
  static normalizePhone(raw: string): string | null {
    if (!raw) return null;
    const digits = String(raw).replace(/\D/g, '');
    if (!digits) return null;
    if (digits.startsWith('9627') && digits.length === 12) return `+${digits}`;
    if (digits.startsWith('07') && digits.length === 10) return `+962${digits.slice(1)}`;
    if (digits.startsWith('7') && digits.length === 9) return `+962${digits}`;
    // Fallback: treat as already international (must contain country code).
    if (digits.length >= 10 && digits.length <= 15) return `+${digits}`;
    return null;
  }

  private validatePassword(password: string): string {
    const pwd = String(password ?? '');
    if (pwd.length < MIN_PASSWORD_LEN) {
      throw new BadRequestException('password_too_short');
    }
    if (pwd.length > MAX_PASSWORD_LEN) {
      throw new BadRequestException('password_too_long');
    }
    return pwd;
  }

  /**
   * Called by an AUTHENTICATED Firebase session (freshly verified via OTP)
   * to attach a password + phone to the signed-in user.
   */
  async setPasswordForFirebaseUid(
    firebaseUid: string,
    phoneRaw: string | null,
    password: string,
  ): Promise<{ ok: true; phone: string }> {
    const uid = String(firebaseUid ?? '').trim();
    if (!uid) throw new UnauthorizedException('firebase_uid_missing');

    const pwd = this.validatePassword(password);
    const phone = PhonePasswordService.normalizePhone(phoneRaw ?? '');
    if (!phone) throw new BadRequestException('invalid_phone');

    await this.ensureSchema();
    const hash = await bcrypt.hash(pwd, BCRYPT_ROUNDS);

    try {
      await this.withClient(async (client) => {
        // Ensure the row exists for this firebase_uid (defensive — normally created by UsersService).
        await client.query(
          `INSERT INTO users (firebase_uid, role, is_active)
           VALUES ($1, 'customer', TRUE)
           ON CONFLICT (firebase_uid) DO NOTHING`,
          [uid],
        );

        // If another account already owns this phone, release it there first so a user can re-register.
        await client.query(
          `UPDATE users SET phone = NULL WHERE phone = $1 AND firebase_uid <> $2`,
          [phone, uid],
        );

        const up = await client.query(
          `UPDATE users
              SET phone = $2,
                  password_hash = $3,
                  password_updated_at = NOW()
            WHERE firebase_uid = $1`,
          [uid, phone, hash],
        );
        if ((up.rowCount ?? 0) < 1) {
          throw new ServiceUnavailableException('user_update_failed');
        }
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`[PhonePassword] set_password failed uid=${uid} phone=${phone}: ${msg}`);
      throw err;
    }

    this.logger.log(`[PhonePassword] set_password uid=${uid} phone=${phone}`);
    return { ok: true, phone };
  }

  /**
   * After Firebase phone OTP sign-in: ensure the ID token's `phone_number`
   * matches the requested E.164 phone, then persist the new password (same as
   * [setPasswordForFirebaseUid]).
   */
  async forgotPasswordAfterPhoneOtpVerification(
    firebaseUid: string,
    decoded: DecodedIdToken,
    phoneRaw: string | null,
    password: string,
  ): Promise<{ ok: true; phone: string }> {
    const uid = String(firebaseUid ?? '').trim();
    if (!uid) throw new UnauthorizedException('firebase_uid_missing');

    const phone = PhonePasswordService.normalizePhone(phoneRaw ?? '');
    if (!phone) throw new BadRequestException('invalid_phone');

    const tokenPhone = decoded.phone_number
      ? PhonePasswordService.normalizePhone(String(decoded.phone_number))
      : null;
    if (!tokenPhone || tokenPhone !== phone) {
      throw new BadRequestException('phone_mismatch');
    }

    return this.setPasswordForFirebaseUid(uid, phone, password);
  }

  /**
   * Registration entrypoint used by Flutter after OTP verification.
   * Verifies the Firebase ID token and persists phone + password hash in `users`.
   */
  async registerWithFirebaseToken(
    firebaseTokenRaw: string,
    phoneRaw: string,
    password: string,
  ): Promise<{ ok: true; firebaseUid: string; phone: string }> {
    const firebaseToken = String(firebaseTokenRaw ?? '').trim();
    if (!firebaseToken) throw new UnauthorizedException('firebase_token_required');
    const phone = PhonePasswordService.normalizePhone(phoneRaw ?? '');
    if (!phone) throw new BadRequestException('invalid_phone');
    const pwd = this.validatePassword(password);

    let decoded: DecodedIdToken;
    try {
      decoded = await getFirebaseAuth().verifyIdToken(firebaseToken);
    } catch {
      throw new UnauthorizedException('invalid_firebase_token');
    }
    const firebaseUid = String(decoded.uid ?? '').trim();
    if (!firebaseUid) throw new UnauthorizedException('firebase_uid_missing');

    // If token contains phone_number, ensure it matches the requested phone.
    const tokenPhone = decoded.phone_number
      ? PhonePasswordService.normalizePhone(String(decoded.phone_number))
      : null;
    if (tokenPhone && tokenPhone !== phone) {
      throw new BadRequestException('phone_mismatch');
    }

    console.log('firebase_uid:', firebaseUid);
    console.log('🔥 firebase_uid:', firebaseUid);
    this.logger.log(`[PhonePassword] register_hit uid=${firebaseUid} phone=${phone}`);
    await this.setPasswordForFirebaseUid(firebaseUid, phone, pwd);
    console.log('USER INSERTED');
    console.log('🔥 USER INSERTED');
    this.logger.log(`[PhonePassword] register_insert_ok uid=${firebaseUid}`);
    return { ok: true, firebaseUid, phone };
  }

  /**
   * Public (no Firebase token required). Verifies phone + password, returns a
   * fresh Firebase custom token the Flutter client can use to sign in.
   */
  async loginWithPhonePassword(
    phoneRaw: string,
    password: string,
  ): Promise<{
    token: string;
    customToken: string;
    firebaseUid: string;
    phone: string;
    role: string;
    userId: string;
  }> {
    console.log('LOGIN HIT');
    const phone = PhonePasswordService.normalizePhone(phoneRaw ?? '');
    if (!phone) throw new BadRequestException('invalid_phone');
    const pwd = String(password ?? '');
    if (pwd.length === 0) throw new BadRequestException('password_required');
    const phoneDigits = phone.replace(/\D/g, '');

    await this.ensureSchema();

    const row = await this.withClient(async (client) => {
      const r = await client.query(
        `SELECT id, firebase_uid, password_hash, role, is_active
         FROM users
         WHERE phone = $1
            OR regexp_replace(COALESCE(phone, ''), '\D', '', 'g') = $2
         LIMIT 1`,
        [phone, phoneDigits],
      );
      return r.rows[0] as
        | { id: string; firebase_uid: string; password_hash: string | null; role: string; is_active: boolean }
        | undefined;
    });

    if (!row) {
      // Intentionally generic to avoid user enumeration.
      throw new UnauthorizedException('INVALID PHONE OR PASSWORD');
    }
    if (!row.is_active) {
      throw new UnauthorizedException('account_disabled');
    }
    if (!row.password_hash) {
      throw new UnauthorizedException('password_not_set');
    }

    const ok = await bcrypt.compare(pwd, row.password_hash);
    if (!ok) {
      throw new UnauthorizedException('INVALID PHONE OR PASSWORD');
    }

    const firebaseUid = String(row.firebase_uid ?? '').trim();
    if (!firebaseUid) {
      throw new ServiceUnavailableException('firebase_uid_missing');
    }
    const userId = String(row.id ?? '').trim();
    if (!userId) throw new ServiceUnavailableException('user_id_missing');
    const role = String(row.role ?? 'customer').trim() || 'customer';

    let customToken: string;
    try {
      customToken = await getFirebaseAuth().createCustomToken(firebaseUid);
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`[PhonePassword] createCustomToken failed uid=${firebaseUid}: ${msg}`);
      throw new ServiceUnavailableException('token_mint_failed');
    }

    console.log('USER ROLE:', role);
    console.log('🔥 USER ROLE:', role);
    this.logger.log(`[PhonePassword] login_ok uid=${firebaseUid} phone=${phone} role=${role}`);
    const token = signBackendSessionToken({ uid: firebaseUid, userId, role });
    return { token, customToken, firebaseUid, phone, role, userId };
  }
}
