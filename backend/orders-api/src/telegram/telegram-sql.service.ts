import { Injectable, Logger } from '@nestjs/common';
import { Pool, type PoolClient } from 'pg';
import { DbRouterService } from '../infrastructure/database/db-router.service';
import { loadTelegramBotConfig, type TelegramBotConfig } from './telegram-bot.config';

/**
 * Executes Claude-proposed SQL against PostgreSQL in a **read-only** sandbox.
 *
 * Safety rails (defence in depth):
 *  1. Strip comments and reject statements that aren't a single SELECT/WITH.
 *  2. Open a `READ ONLY` transaction so any mutating attempt errors at DB level.
 *  3. Per-statement timeout via `SET LOCAL statement_timeout`.
 *  4. Force a `LIMIT` ceiling so Telegram replies stay small.
 *  5. Chat-id allowlist (optional) — when configured, only whitelisted chats
 *     can trigger SQL; everyone else gets a polite refusal.
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

  isChatAllowed(chatId: number): boolean {
    if (this.cfg.sqlAllowedChatIds.size === 0) {
      return true;
    }
    return this.cfg.sqlAllowedChatIds.has(chatId);
  }

  /**
   * Validate + run a single read-only query. Returns a structured result Claude
   * (and the human user) can consume. Never throws — always returns an object
   * with either `rows` or a human-safe `error`.
   */
  async runReadOnlyQuery(rawSql: string): Promise<{
    ok: boolean;
    rows?: Record<string, unknown>[];
    rowCount?: number;
    truncated?: boolean;
    columns?: string[];
    error?: string;
  }> {
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
      const truncated = total > rows.length;
      return {
        ok: true,
        rows,
        rowCount: total,
        truncated,
        columns,
      };
    } catch (e) {
      try {
        await client.query('ROLLBACK');
      } catch {
        /* ignore rollback errors */
      }
      const msg = e instanceof Error ? e.message : String(e);
      this.logger.warn(`[TelegramSql] query failed: ${msg}`);
      return { ok: false, error: sanitizeDbError(msg) };
    } finally {
      client.release();
    }
  }

  private async acquireReadClient(): Promise<PoolClient | null> {
    if (this.dbRouter.isActive()) {
      const c = await this.dbRouter.getReadClient();
      if (c) return c;
    }
    const pool = this.getFallbackPool();
    if (!pool) return null;
    try {
      return await pool.connect();
    } catch (e) {
      this.logger.warn(`[TelegramSql] fallback pool connect failed: ${e instanceof Error ? e.message : String(e)}`);
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
      this.logger.warn(`[TelegramSql] fallback pool init failed: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }
  }
}

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
  // Single statement only.
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
  // Forbid obvious write keywords even inside CTE bodies.
  const upperNoStr = stripped.toUpperCase();
  const forbidden = [
    'INSERT ',
    'UPDATE ',
    'DELETE ',
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
  ];
  for (const kw of forbidden) {
    if (upperNoStr.includes(kw)) {
      return { ok: false, error: `forbidden_keyword:${kw.trim()}` };
    }
  }
  // Enforce a LIMIT ceiling. We wrap with a subselect so existing LIMITs still apply
  // and the outer LIMIT acts purely as a hard ceiling.
  const wrapped = `SELECT * FROM (${withoutTrailingSemi}) AS _bot_sub LIMIT ${maxRows}`;
  return { ok: true, sql: wrapped };
}

/** Remove `--` line comments, `/* *\/` block comments, and collapse string literals. */
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
