#!/bin/sh
# docker-entrypoint.sh — orders-api
#
# Boot rules (Railway / Docker):
#   1. On each container start, run SQL migrations via Node (same order as repo:
#      `node scripts/apply-all-sql.cjs`) so Railway deploys stay in sync with
#      sql/migrations (001…028). Requires DATABASE_URL / ORDERS_DATABASE_URL.
#   2. If migrations fail, log a warning and still start the server so health
#      checks can surface /health while operators fix the DB.
#   3. Exactly one `exec` hands PID 1 to the main process.
set -u

RUN_DB_BOOTSTRAP_ON_START="${RUN_DB_BOOTSTRAP_ON_START:-1}"
DB_URL="${DATABASE_URL:-${ORDERS_DATABASE_URL:-}}"

run_sql_migrations() {
  if [ "$RUN_DB_BOOTSTRAP_ON_START" = "0" ]; then
    echo "[entrypoint] RUN_DB_BOOTSTRAP_ON_START=0 — skipping SQL migrations."
    return 0
  fi

  if [ -z "$DB_URL" ]; then
    echo "[entrypoint] WARN: DATABASE_URL / ORDERS_DATABASE_URL not set — skipping SQL migrations."
    return 0
  fi

  if [ ! -f scripts/apply-all-sql.cjs ]; then
    echo "[entrypoint] WARN: scripts/apply-all-sql.cjs not found — skipping SQL migrations."
    return 0
  fi

  echo "[entrypoint] running SQL migrations: node scripts/apply-all-sql.cjs"
  if ! node scripts/apply-all-sql.cjs; then
    echo "[entrypoint] WARN: apply-all-sql.cjs failed — continuing to start server."
  fi
}

echo "[entrypoint] Starting server (after migrations)…"
run_sql_migrations

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec npm run start:prod
fi
