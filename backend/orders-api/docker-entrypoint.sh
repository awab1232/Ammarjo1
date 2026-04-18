#!/bin/sh
# docker-entrypoint.sh — orders-api
#
# Boot rules (Railway / Docker):
#   1. On each container start, run SQL migrations via Node (`apply-all-sql.cjs`)
#      so Railway deploys stay in sync with sql/migrations. Requires DATABASE_URL /
#      ORDERS_DATABASE_URL. Applied files are tracked in schema_migrations; the
#      runner stops on first SQL error (no partial forward progress within one boot).
#   2. If migrations fail, exit non-zero so the platform restarts / surfaces failure.
#      To skip migrations entirely: RUN_DB_BOOTSTRAP_ON_START=0.
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
    echo "[entrypoint] FATAL: apply-all-sql.cjs failed — exiting so the DB is not started with a bad schema."
    exit 1
  fi
}

echo "[entrypoint] Starting server (after migrations)…"
# If Railway/docker CMD already runs apply-all-sql.cjs (see railway.json), skip duplicate.
_cmdline="$*"
if [ -n "$_cmdline" ] && echo "$_cmdline" | grep -Fq 'apply-all-sql.cjs'; then
  echo "[entrypoint] start command includes apply-all-sql.cjs — skipping entrypoint migrations."
else
  run_sql_migrations
fi

if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec npm run start:prod
fi
