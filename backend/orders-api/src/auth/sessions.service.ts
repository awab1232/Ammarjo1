import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { buildPgPoolConfig } from '../infrastructure/database/pg-ssl';

export interface SessionRow {
  id: string;
  firebase_uid: string;
  device_id: string;
  device_name: string;
  device_os: string;
  app_version: string;
  ip_address: string | null;
  is_trusted: boolean;
  last_login_at: string;
  created_at: string;
}

@Injectable()
export class SessionsService {
  private readonly pool: Pool | null;
  private schemaReady = false;

  constructor() {
    const url = process.env.DATABASE_URL?.trim();
    this.pool = url
      ? new Pool(
          buildPgPoolConfig(url, {
            max: 4,
            idleTimeoutMillis: 30_000,
          }),
        )
      : null;
  }

  private requireDb(): Pool {
    if (!this.pool) throw new ServiceUnavailableException('sessions database not configured');
    return this.pool;
  }

  private async withClient<T>(fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.requireDb().connect();
    try {
      if (!this.schemaReady) {
        await this.ensureSchema(client);
        this.schemaReady = true;
      }
      return await fn(client);
    } finally {
      client.release();
    }
  }

  private async ensureSchema(client: PoolClient): Promise<void> {
    await client.query(`
      CREATE TABLE IF NOT EXISTS user_sessions (
        id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
        firebase_uid  TEXT    NOT NULL,
        device_id     TEXT    NOT NULL,
        device_name   TEXT    NOT NULL DEFAULT '',
        device_os     TEXT    NOT NULL DEFAULT '',
        app_version   TEXT    NOT NULL DEFAULT '',
        ip_address    TEXT,
        is_trusted    BOOLEAN NOT NULL DEFAULT TRUE,
        last_login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS idx_user_sessions_uid_device
        ON user_sessions (firebase_uid, device_id);
      CREATE INDEX IF NOT EXISTS idx_user_sessions_uid_last
        ON user_sessions (firebase_uid, last_login_at DESC);
      CREATE INDEX IF NOT EXISTS idx_user_sessions_last_login
        ON user_sessions (last_login_at DESC);
    `);
  }

  /** Register or refresh a device session (upsert by firebase_uid + device_id). */
  async upsertSession(data: {
    firebaseUid: string;
    deviceId: string;
    deviceName: string;
    deviceOs: string;
    appVersion: string;
    ipAddress: string | null;
  }): Promise<SessionRow> {
    return this.withClient(async (client) => {
      const res = await client.query<SessionRow>(
        `INSERT INTO user_sessions
           (firebase_uid, device_id, device_name, device_os, app_version, ip_address, last_login_at)
         VALUES ($1, $2, $3, $4, $5, $6, NOW())
         ON CONFLICT (firebase_uid, device_id) DO UPDATE SET
           device_name   = EXCLUDED.device_name,
           device_os     = EXCLUDED.device_os,
           app_version   = EXCLUDED.app_version,
           ip_address    = EXCLUDED.ip_address,
           last_login_at = NOW()
         RETURNING *`,
        [data.firebaseUid, data.deviceId, data.deviceName, data.deviceOs, data.appVersion, data.ipAddress],
      );
      return res.rows[0];
    });
  }

  /** List active sessions for a specific user. */
  async listForUser(firebaseUid: string): Promise<SessionRow[]> {
    return this.withClient(async (client) => {
      const res = await client.query<SessionRow>(
        `SELECT * FROM user_sessions
         WHERE firebase_uid = $1
         ORDER BY last_login_at DESC`,
        [firebaseUid],
      );
      return res.rows;
    });
  }

  /** List all sessions (admin). */
  async listAll(limit = 50, offset = 0): Promise<{ rows: SessionRow[]; total: number }> {
    return this.withClient(async (client) => {
      const [dataRes, countRes] = await Promise.all([
        client.query<SessionRow>(
          `SELECT * FROM user_sessions ORDER BY last_login_at DESC LIMIT $1 OFFSET $2`,
          [limit, offset],
        ),
        client.query<{ count: string }>(`SELECT COUNT(*) AS count FROM user_sessions`),
      ]);
      return { rows: dataRes.rows, total: parseInt(countRes.rows[0]?.count ?? '0', 10) };
    });
  }

  /** Delete a single session by id. */
  async deleteSession(id: string): Promise<void> {
    return this.withClient(async (client) => {
      await client.query(`DELETE FROM user_sessions WHERE id = $1`, [id]);
    });
  }

  /** Delete all sessions for a user (force logout all devices). */
  async deleteAllForUser(firebaseUid: string): Promise<void> {
    return this.withClient(async (client) => {
      await client.query(`DELETE FROM user_sessions WHERE firebase_uid = $1`, [firebaseUid]);
    });
  }
}
