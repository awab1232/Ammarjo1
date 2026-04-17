import { Injectable, Logger } from '@nestjs/common';
import { loadTelegramBotConfig } from './telegram-bot.config';
import { TelegramSqlService } from './telegram-sql.service';

interface SchemaCache {
  text: string;
  fetchedAt: number;
  tableCount: number;
}

/**
 * Loads the public-schema shape from PostgreSQL once per TTL window and
 * produces a compact, token-efficient summary that can be injected into
 * Claude's system prompt.
 *
 * Rationale: Claude otherwise has to burn tool-use iterations asking
 * `information_schema` which frequently blew past the 4-iteration cap.
 * Giving it the schema up-front turns most "list data" questions into a
 * single Claude → SELECT → reply round trip.
 */
@Injectable()
export class TelegramSchemaService {
  private readonly logger = new Logger(TelegramSchemaService.name);
  private cache: SchemaCache | null = null;

  /** Cache TTL in ms. Env-overridable so ops can shorten it after a migration. */
  private readonly ttlMs: number = Math.max(
    30_000,
    Number(process.env.TELEGRAM_BOT_SCHEMA_TTL_MS || 5 * 60_000),
  );

  /** Hard caps to keep the system prompt from ballooning on large DBs. */
  private readonly maxTables: number = Math.max(
    5,
    Number(process.env.TELEGRAM_BOT_SCHEMA_MAX_TABLES || 80),
  );
  private readonly maxColumnsPerTable: number = Math.max(
    3,
    Number(process.env.TELEGRAM_BOT_SCHEMA_MAX_COLUMNS || 25),
  );

  constructor(private readonly sql: TelegramSqlService) {}

  /** Returns the formatted schema string for prompt injection; never throws. */
  async getSchemaForPrompt(): Promise<string> {
    const now = Date.now();
    if (this.cache && now - this.cache.fetchedAt < this.ttlMs) {
      return this.cache.text;
    }
    const text = await this.loadFresh();
    this.cache = { text, fetchedAt: now, tableCount: this.estimateTableCount(text) };
    return text;
  }

  /** Force the next getSchemaForPrompt() call to refetch. */
  invalidate(): void {
    this.cache = null;
  }

  private async loadFresh(): Promise<string> {
    const res = await this.sql.fetchPublicSchemaRows();
    if (!res.ok || !res.rows || res.rows.length === 0) {
      this.logger.warn(
        `[TelegramSchema] introspection unavailable: ${res.error ?? 'empty'}`,
      );
      return [
        '(Schema introspection unavailable right now.',
        'You may still call the run_read_query tool against information_schema.tables',
        'to explore the database manually.)',
      ].join(' ');
    }
    return this.formatRows(res.rows);
  }

  /**
   * Group by table and emit:
   *   tablename(col1 type, col2 type NULL, …)
   *
   * `NULL` suffix marks nullable columns; missing suffix = NOT NULL. Types are
   * the raw `information_schema.data_type` values (e.g. `text`, `bigint`,
   * `timestamp with time zone`).
   */
  private formatRows(
    rows: Array<{
      table_name: string;
      column_name: string;
      data_type: string;
      is_nullable: string;
    }>,
  ): string {
    const byTable = new Map<string, Array<{ col: string; type: string; nullable: boolean }>>();
    for (const r of rows) {
      const bucket = byTable.get(r.table_name) ?? [];
      bucket.push({
        col: r.column_name,
        type: r.data_type,
        nullable: r.is_nullable === 'YES',
      });
      byTable.set(r.table_name, bucket);
    }

    const tableNames = Array.from(byTable.keys()).sort();
    const totalTables = tableNames.length;
    const shown = tableNames.slice(0, this.maxTables);

    const lines: string[] = [];
    lines.push(`PostgreSQL schema "public" — ${totalTables} table(s).`);
    if (shown.length < totalTables) {
      lines.push(
        `Showing first ${shown.length}; use run_read_query against information_schema for the rest.`,
      );
    }
    for (const t of shown) {
      const cols = byTable.get(t) ?? [];
      const shownCols = cols.slice(0, this.maxColumnsPerTable);
      const more = cols.length - shownCols.length;
      const pieces = shownCols.map(
        (c) => `${c.col} ${c.type}${c.nullable ? ' NULL' : ''}`,
      );
      if (more > 0) pieces.push(`+${more} more`);
      lines.push(`- ${t}(${pieces.join(', ')})`);
    }
    return lines.join('\n');
  }

  private estimateTableCount(text: string): number {
    return text.split('\n').filter((l) => l.startsWith('- ')).length;
  }
}

/** Exposed only so unit tests can snapshot the config block if needed. */
export function schemaPromptHeader(): string {
  const cfg = loadTelegramBotConfig();
  return [
    'The live database schema is provided below. Use these table and column names verbatim.',
    `Only ${cfg.sqlEnabled ? 'read and write tools are registered' : 'tools are disabled'}.`,
  ].join(' ');
}
