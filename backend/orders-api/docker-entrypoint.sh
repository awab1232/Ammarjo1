#!/bin/sh
# docker-entrypoint.sh — orders-api
#
# Boot rules (Railway / Docker):
#   1. Run SQL migrations via Node (apply-all-sql.cjs) unless disabled.
#   2. Then exec the container command (Dockerfile CMD: npm run start:prod).
#   3. Do not put "node … && npm …" in Railway startCommand — a single argv breaks exec;
#      keep migrations here only, and set startCommand to "npm run start:prod" (or omit it).
#   4. If migrations fail: exit 1. To skip: RUN_DB_BOOTSTRAP_ON_START=0.
set -u

RUN_DB_BOOTSTRAP_ON_START="${RUN_DB_BOOTSTRAP_ON_START:-1}"
DB_URL="${DATABASE_URL:-}"

run_sql_migrations() {
  if [ "$RUN_DB_BOOTSTRAP_ON_START" = "0" ]; then
    echo "[entrypoint] RUN_DB_BOOTSTRAP_ON_START=0 — skipping SQL migrations."
    return 0
  fi

  if [ -z "$DB_URL" ]; then
    echo "[entrypoint] WARN: DATABASE_URL not set — skipping SQL migrations."
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
  echo "[entrypoint] SQL migrations finished OK."
}

echo "[entrypoint] orders-api starting (pid $$)…"
run_sql_migrations

# Railway sometimes passes startCommand as ONE argv (e.g. "npm run start:prod"); exec needs a shell.
if [ "$#" -eq 1 ] && echo "$1" | grep -q ' '; then
  echo "[entrypoint] exec via /bin/sh -c (single argv with spaces)"
  exec /bin/sh -c "set -e
$1"
fi

if [ "$#" -gt 0 ]; then
  echo "[entrypoint] exec:" "$@"
  exec "$@"
else
  echo "[entrypoint] no CMD args — exec npm run start:prod"
  exec npm run start:prod
fi
