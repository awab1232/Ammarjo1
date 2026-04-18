/**
 * Applies every numbered SQL file in sql/migrations in ascending order (001…028).
 * Uses the `postgres` driver so multi-statement files (DO $$ … $$, functions) work
 * without requiring the `psql` CLI on the machine.
 *
 * Usage (Railway / local):
 *   cd backend/orders-api && npm install
 *   export DATABASE_URL="postgresql://USER:PASS@HOST:PORT/DB?sslmode=require"
 *   npm run db:apply-all-sql
 *
 * On Railway: run the same command in a one-off shell where DATABASE_URL is
 * injected from the Postgres plugin / service variables.
 *
 * Optional: SKIP_SQL_FILES=024_seed_dev_stores_and_technicians.sql,026_demo_home_seed.sql
 *   (comma-separated basenames) to skip heavy demo seeds on a fresh DB.
 *
 * After success: curl "$BASE/api/stores/public?limit=10" should list ≥4 stores
 * when 028_railway_seed_targeted.sql ran (and source:"db" in JSON if applicable).
 */
'use strict';

const fs = require('fs');
const path = require('path');

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
    console.error('Install dependency: npm install postgres --save-dev');
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

  for (const f of files) {
    if (skip.has(f)) {
      console.error(`[skip] ${f}`);
      continue;
    }
    const fp = path.join(migrationsDir, f);
    const body = fs.readFileSync(fp, 'utf8');
    console.error(`[apply] ${f} …`);
    await sql.unsafe(body);
    console.error(`[ok]   ${f}`);
  }

  await sql.end({ timeout: 10 });
  console.error('All migration files applied successfully.');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
