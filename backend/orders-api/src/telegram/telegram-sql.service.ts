import { Injectable, Logger } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';
import { loadTelegramBotConfig, type TelegramBotConfig } from './telegram-bot.config';

export interface SqlQueryResult {
  ok: boolean;
  rows?: Record<string, unknown>[];
  rowCount?: number;
  truncated?: boolean;
  columns?: string[];
  error?: string;
}

export interface SqlWriteResult {
  ok: boolean;
  rowCount?: number;
  verb?: 'INSERT' | 'UPDATE' | 'DELETE';
  error?: string;
}

/**
 * Executes SQL proposed by Claude against PostgreSQL in a controlled sandbox.
 *
 * There are two entry points:
 *
 *   - [runReadOnlyQuery] — single SELECT / WITH-select, wrapped in a
 *     `READ ONLY` transaction with a LIMIT ceiling.
 *   - [runWriteQuery] — single INSERT / UPDATE / DELETE executed in a normal
 *     transaction. DDL, multi-statement, and unconditional UPDATE/DELETE are
 *     rejected outright.
 *
 * Both paths enforce a per-statement `statement_timeout` and never throw — all
 * errors come back as a structured result so the bot can keep the user in the
 * loop.
 */
@Injectable()
export class TelegramSqlService {
  private readonly logger = new Logger(TelegramSqlService.name);
  private readonly cfg: TelegramBotConfig = loadTelegramBotConfig();

  /** Lazily-created fallback pool for when DbRouter isn't active. */
  private fallbackPool: Pool | null = null;

  constructor(private readonly dbRouter: DbRouterService) {}

  isEnabled(): boolean {
    return this.cfg.sqlEnabled;
  }

  isWriteEnabled(): boolean {
    return this.cfg.sqlEnabled && this.cfg.writeEnabled;
  }

  isChatAllowed(chatId: number): boolean {
    if (this.cfg.sqlAllowedChatIds.size === 0) {
      // When no SQL-specific list is set we inherit from the global allowlist,
      // which the caller (bot service) already enforces.
      return true;
    }
    return this.cfg.sqlAllowedChatIds.has(chatId);
  }

  /* ------------------------------------------------------------------ */
  /* READ PATH                                                           */
  /* ------------------------------------------------------------------ */

  async runReadOnlyQuery(rawSql: string): Promise<SqlQueryResult> {
    const sanitized = sanitizeSelectSql(rawSql, this.cfg.maxSqlRows);
    if (!sanitized.ok) {
      return { ok: false, error: sanitized.error };
    }

    const client = await this.acquireReadClient();
    if (!client) {
      return { ok: false, error: 'database_unavailable' };
    }

    try {
      await client.query('BEGIN READ ONLY');
      await client.query(`SET LOCAL statement_timeout = ${this.cfg.sqlStatementTimeoutMs}`);
      const res = await client.query(sanitized.sql);
      await client.query('COMMIT');

      const rows = Array.isArray(res.rows) ? res.rows.slice(0, this.cfg.maxSqlRows) : [];
      const columns = Array.isArray(res.fields) ? res.fields.map((f) => f.name) : [];
      const total = typeof res.rowCount === 'number' ? res.rowCount : rows.length;
      return {
        ok: true,
        rows,
        rowCount: total,
        truncated: total > rows.length,
        columns,
      };
    } catch (e) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* ignore rollback errors */
      }
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.warn(`[TelegramSql] read failed: ${msg}`);
      return { ok: false, error: sanitizeDbError(msg) };
    } finally {
      client.release();
    }
  }

  /* ------------------------------------------------------------------ */
  /* WRITE PATH                                                          */
  /* ------------------------------------------------------------------ */

  /**
   * Validates a write-intent SQL string **without** executing it — used when
   * presenting a confirmation prompt to the user.
   */
  validateWriteSql(rawSql: string): { ok: true; sql: string; verb: 'INSERT' | 'UPDATE' | 'DELETE' } | { ok: false; error: string } {
    return sanitizeWriteSql(rawSql);
  }

  async runWriteQuery(rawSql: string): Promise<SqlWriteResult> {
    if (!this.isWriteEnabled()) {
      return { ok: false, error: 'writes_disabled' };
    }
    const sanitized = sanitizeWriteSql(rawSql);
    if (!sanitized.ok) {
      return { ok: false, error: sanitized.error };
    }
    const client = await this.acquireWriteClient();
    if (!client) {
      return { ok: false, error: 'database_unavailable' };
    }
    try {
      await client.query('BEGIN');
      await client.query(`SET LOCAL statement_timeout = ${this.cfg.sqlStatementTimeoutMs}`);
      const res = await client.query(sanitized.sql);
      await client.query('COMMIT');
      return {
        ok: true,
        rowCount: typeof res.rowCount === 'number' ? res.rowCount : 0,
        verb: sanitized.verb,
      };
    } catch (e) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* ignore rollback errors */
      }
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.warn(`[TelegramSql] write failed: ${msg}`);
      return { ok: false, error: sanitizeDbError(msg), verb: sanitized.verb };
    } finally {
      client.release();
    }
  }

  /* ------------------------------------------------------------------ */
  /* Pool helpers                                                        */
  /* ------------------------------------------------------------------ */

  private async acquireReadClient(): Promise<PoolClient | null> {
    if (this.dbRouter.isActive()) {
      const c = await this.dbRouter.getReadClient();
      if (c) return c;
    }
    return this.acquireFallbackClient();
  }

  private async acquireWriteClient(): Promise<PoolClient | null> {
    if (this.dbRouter.isActive()) {
      const c = await this.dbRouter.getWriteClient();
      if (c) return c;
    }
    return this.acquireFallbackClient();
  }

  private async acquireFallbackClient(): Promise<PoolClient | null> {
    const pool = this.getFallbackPool();
    if (!pool) return null;
    try {
      return await pool.connect();
    } catch (e) {
      this.logger.warn(
        `[TelegramSql] fallback pool connect failed: ${e instanceof Error ? e.message : String(e)}`,
      );
      return null;
    }
  }

  private getFallbackPool(): Pool | null {
    if (this.fallbackPool) return this.fallbackPool;
    const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
    if (!url) return null;
    try {
      this.fallbackPool = new Pool({
        connectionString: url,
        max: 2,
        idleTimeoutMillis: 10_000,
      });
      this.fallbackPool.on('connect', (c) => {
        void c.query("SET client_encoding TO 'UTF8'").catch(() => undefined);
      });
      return this.fallbackPool;
    } catch (e) {
      this.logger.warn(
        `[TelegramSql] fallback pool init failed: ${e instanceof Error ? e.message : String(e)}`,
      );
      return null;
    }
  }
}

/* ====================================================================== */
/* Sanitisers                                                              */
/* ====================================================================== */

/**
 * Returns either a safe, LIMIT-capped SELECT string or an `error` reason.
 * Intentionally conservative — we would rather reject a valid query than run
 * something dangerous.
 */
export function sanitizeSelectSql(
  rawSql: string,
  maxRows: number,
): { ok: true; sql: string } | { ok: false; error: string } {
  if (typeof rawSql !== 'string') {
    return { ok: false, error: 'sql_not_string' };
  }
  const stripped = stripSqlCommentsAndStrings(rawSql).trim();
  if (stripped.length === 0) {
    return { ok: false, error: 'sql_empty' };
  }
  const withoutTrailingSemi = stripped.replace(/;+\s*$/g, '');
  if (withoutTrailingSemi.includes(';')) {
    return { ok: false, error: 'multi_statement_not_allowed' };
  }
  const head = withoutTrailingSemi.slice(0, 6).toUpperCase();
  const headLong = withoutTrailingSemi.slice(0, 4).toUpperCase();
  const isSelect = head.startsWith('SELECT');
  const isCte = headLong.startsWith('WITH');
  if (!isSelect && !isCte) {
    return { ok: false, error: 'only_select_allowed' };
  }
  const forbiddenCheck = containsForbiddenKeyword(stripped, /* allowDml= */ false);
  if (forbiddenCheck) {
    return { ok: false, error: forbiddenCheck };
  }
  const wrapped = `SELECT * FROM (${withoutTrailingSemi}) AS _bot_sub LIMIT ${maxRows}`;
  return { ok: true, sql: wrapped };
}

/**
 * Validates a single INSERT / UPDATE / DELETE statement.
 *
 * Rules:
 *  - single statement only (no trailing or mid-stream semicolons)
 *  - must start with INSERT / UPDATE / DELETE
 *  - DDL / TRUNCATE / COPY / etc. are rejected
 *  - UPDATE and DELETE MUST include a WHERE clause (to prevent
 *    "DELETE FROM stores" wiping the table)
 */
export function sanitizeWriteSql(
  rawSql: string,
): { ok: true; sql: string; verb: 'INSERT' | 'UPDATE' | 'DELETE' } | { ok: false; error: string } {
  if (typeof rawSql !== 'string') {
    return { ok: false, error: 'sql_not_string' };
  }
  const stripped = stripSqlCommentsAndStrings(rawSql).trim();
  if (stripped.length === 0) {
    return { ok: false, error: 'sql_empty' };
  }
  const withoutTrailingSemi = stripped.replace(/;+\s*$/g, '');
  if (withoutTrailingSemi.includes(';')) {
    return { ok: false, error: 'multi_statement_not_allowed' };
  }
  const upper = withoutTrailingSemi.toUpperCase();
  let verb: 'INSERT' | 'UPDATE' | 'DELETE';
  if (upper.startsWith('INSERT ')) verb = 'INSERT';
  else if (upper.startsWith('UPDATE ')) verb = 'UPDATE';
  else if (upper.startsWith('DELETE ')) verb = 'DELETE';
  else return { ok: false, error: 'only_insert_update_delete_allowed' };

  // Require WHERE for UPDATE / DELETE to avoid catastrophic whole-table ops.
  if ((verb === 'UPDATE' || verb === 'DELETE') && !/\bWHERE\b/i.test(withoutTrailingSemi)) {
    return { ok: false, error: `${verb.toLowerCase()}_requires_where_clause` };
  }

  const forbiddenCheck = containsForbiddenKeyword(stripped, /* allowDml= */ true);
  if (forbiddenCheck) {
    return { ok: false, error: forbiddenCheck };
  }

  return { ok: true, sql: withoutTrailingSemi, verb };
}

/** Shared forbidden-keyword scan. When `allowDml` is true we skip INSERT/UPDATE/DELETE. */
function containsForbiddenKeyword(sql: string, allowDml: boolean): string | null {
  const upper = sql.toUpperCase();
  const banned: string[] = [
    'DROP ',
    'ALTER ',
    'CREATE ',
    'TRUNCATE ',
    'GRANT ',
    'REVOKE ',
    'COPY ',
    'VACUUM ',
    'REINDEX ',
    'REFRESH ',
    'CLUSTER ',
    'ANALYZE ',
    'LOCK ',
    'CALL ',
    'DO ',
    'EXECUTE ',
    'SECURITY DEFINER',
    'PG_SLEEP',
    'PG_READ_FILE',
    'PG_LS_DIR',
    'PG_TERMINATE_BACKEND',
  ];
  if (!allowDml) {
    banned.push('INSERT ', 'UPDATE ', 'DELETE ');
  }
  for (const kw of banned) {
    if (upper.includes(kw)) {
      return `forbidden_keyword:${kw.trim()}`;
    }
  }
  return null;
}

/** Remove `--` line comments and `/* *\/` block comments. */
function stripSqlCommentsAndStrings(sql: string): string {
  let out = sql;
  out = out.replace(/\/\*[\s\S]*?\*\//g, ' ');
  out = out.replace(/--[^\n\r]*/g, ' ');
  return out;
}

/** Don't leak internal error hints to a chat user; keep the summary short. */
function sanitizeDbError(msg: string): string {
  const firstLine = msg.split('\n', 1)[0] ?? msg;
  return firstLine.slice(0, 240);
}
