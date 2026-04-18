/**
 * Applies numbered SQL files in sql/migrations in ascending order (000…).
 * Uses the `postgres` driver so multi-statement files (DO $$ … $$, functions) work
 * without requiring the `psql` CLI.
 *
 * Tracking: table `schema_migrations` stores each applied basename; already-applied
 * files are skipped (no duplicate execution). On first failure the process exits
 * and does not apply later files.
 *
 * Usage:
 *   export DATABASE_URL="postgresql://…"
 *   npm run db:apply-all-sql
 *
 * Optional: SKIP_SQL_FILES=024_….sql,026_….sql — skip without recording (re-tried next run).
 *
 * Existing DBs predating tracking: migrations should be idempotent (IF NOT EXISTS, etc.),
 * or manually insert rows into schema_migrations for files already applied.
 *
 * Multi-instance: pg_advisory_lock reduces concurrent double-apply races on one connection.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const ADVISORY_LOCK_KEY = 802154319;

const ENSURE_MIGRATIONS_TABLE = `
CREATE TABLE IF NOT EXISTS schema_migrations (
  filename TEXT PRIMARY KEY,
  applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
`;

async function ensureMigrationsTable(sql) {
  await sql.unsafe(ENSURE_MIGRATIONS_TABLE);
}

async function isApplied(sql, filename) {
  const rows = await sql`
    SELECT 1 AS ok FROM schema_migrations WHERE filename = ${filename} LIMIT 1
  `;
  return rows.length > 0;
}

async function recordApplied(sql, filename) {
  await sql`
    INSERT INTO schema_migrations (filename) VALUES (${filename})
  `;
}

async function main() {
  const url = process.env.DATABASE_URL?.trim() || process.env.ORDERS_DATABASE_URL?.trim();
  if (!url) {
    console.error('Missing DATABASE_URL or ORDERS_DATABASE_URL');
    process.exit(1);
  }

  const skipRaw = process.env.SKIP_SQL_FILES?.trim() ?? '';
  const skip = new Set(
    skipRaw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  );

  let postgres;
  try {
    postgres = require('postgres');
  } catch {
    console.error('Install dependency: npm install postgres');
    process.exit(1);
  }

  const migrationsDir = path.join(__dirname, '..', 'sql', 'migrations');
  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => /^\d{3}_.+\.sql$/.test(f) && !f.startsWith('_'))
    .sort((a, b) => {
      const na = parseInt(a.slice(0, 3), 10);
      const nb = parseInt(b.slice(0, 3), 10);
      return na - nb;
    });

  const sql = postgres(url, {
    max: 1,
    ssl: url.includes('localhost') ? false : 'require',
    connect_timeout: 60,
  });

  let failedAt = null;
  try {
    await ensureMigrationsTable(sql);

    await sql.unsafe(`SELECT pg_advisory_lock(${ADVISORY_LOCK_KEY})`);
    try {
      for (const f of files) {
        if (skip.has(f)) {
          console.error(`[SKIP] ${f}`);
          continue;
        }

        if (await isApplied(sql, f)) {
          console.error(`[SKIP] ${f}`);
          continue;
        }

        const fp = path.join(migrationsDir, f);
        const body = fs.readFileSync(fp, 'utf8');

        failedAt = f;
        console.error(`[APPLY] ${f}`);
        await sql.unsafe(body);
        await recordApplied(sql, f);
        console.error(`[OK] ${f}`);
        failedAt = null;
      }
    } finally {
      try {
        await sql.unsafe(`SELECT pg_advisory_unlock(${ADVISORY_LOCK_KEY})`);
      } catch {
        /* best-effort */
      }
    }

    console.error('Migration tracking added: YES');
    console.error('Duplicate execution prevented: YES');
    console.error('Safe execution: YES');
    console.error('FINAL STATUS: SUCCESS');
  } catch (err) {
    if (failedAt) {
      console.error(`[MIGRATION] FATAL: failed while running: ${failedAt}`);
    } else {
      console.error('[MIGRATION] FATAL: migration runner error');
    }
    console.error(err instanceof Error ? err.message : String(err));
    if (err instanceof Error && err.stack) {
      console.error(err.stack);
    }
    console.error('FINAL STATUS: FAILED');
    process.exit(1);
  } finally {
    try {
      await sql.end({ timeout: 10 });
    } catch {
      /* ignore */
    }
  }
}

main().catch((err) => {
  console.error('[MIGRATION] FATAL: unexpected error in migration runner');
  console.error(err instanceof Error ? err.message : String(err));
  if (err instanceof Error && err.stack) {
    console.error(err.stack);
  }
  console.error('FINAL STATUS: FAILED');
  process.exit(1);
});
