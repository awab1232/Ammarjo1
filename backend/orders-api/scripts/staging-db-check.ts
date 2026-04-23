import { Client } from 'pg';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function logJson(kind: string, payload: Record<string, unknown>): void {
  console.log(JSON.stringify({ kind, ...payload }));
}

function loadStagingEnvIfPresent(): void {
  const p = resolve(process.cwd(), '.env.staging');
  if (!existsSync(p)) return;
  const raw = readFileSync(p, 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const idx = t.indexOf('=');
    if (idx <= 0) continue;
    const k = t.slice(0, idx).trim();
    const v = t.slice(idx + 1).trim();
    if (!process.env[k]) process.env[k] = v;
  }
}

async function main(): Promise<void> {
  loadStagingEnvIfPresent();
  const connectionString = process.env.DATABASE_URL?.trim();
  if (!connectionString) {
    logJson('staging_db_missing_tables', { reason: 'DATABASE_URL missing' });
    process.exit(1);
  }

  const requiredTables = ['stores', 'categories', 'products', 'service_requests', 'ratings_reviews', 'event_outbox'];
  const client = new Client({ connectionString });
  try {
    await client.connect();
    await client.query('SELECT 1');
    const q = await client.query<{ tablename: string }>(
      `SELECT tablename
       FROM pg_catalog.pg_tables
       WHERE schemaname = 'public'`,
    );
    const existing = new Set(q.rows.map((r) => r.tablename));
    const missing = requiredTables.filter((t) => !existing.has(t));
    if (missing.length > 0) {
      logJson('staging_db_missing_tables', { missing });
      process.exit(1);
    }
    logJson('staging_db_ready', { requiredTables });
  } catch (e) {
    logJson('staging_db_missing_tables', {
      reason: e instanceof Error ? e.message : String(e),
    });
    process.exit(1);
  } finally {
    await client.end().catch(() => undefined);
  }
}

void main();
