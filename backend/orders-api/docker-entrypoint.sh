#!/bin/sh
# docker-entrypoint.sh — orders-api
#
# Boot rules (Railway / Docker):
#   1. NEVER block the Node server behind DB availability — the container MUST
#      listen on $PORT so platform healthchecks can reach /health even when DB
#      or migrations are broken. Operators will see the error in logs and fix
#      DATABASE_URL; the platform won't kill the pod as "unhealthy" first.
#   2. Migrations are best-effort on boot: we log + continue on failure.
#   3. Exactly one `exec` hands PID 1 to Node so Sentry, signals, and graceful
#      shutdown work.
set -u

DB_WAIT_SECONDS="${DB_WAIT_SECONDS:-30}"
RUN_DB_BOOTSTRAP_ON_START="${RUN_DB_BOOTSTRAP_ON_START:-1}"
DB_URL="${DATABASE_URL:-${ORDERS_DATABASE_URL:-}}"

# Apply migrations in dependency order. 011 must run before 008 so hybrid
# `store_categories` (011) is created first; 008's legacy CREATE IF NOT EXISTS
# then skips without clobbering columns needed by 011's indexes.
MIGRATION_ORDER="
001_create_users.sql
002_create_store_types_categories_stores_products.sql
003_create_catalog_products.sql
004_create_orders.sql
005_create_order_related_cart_notifications.sql
006_create_reviews_ratings.sql
007_create_promotions_coupons_commissions.sql
009_create_service_requests.sql
010_create_wholesale_features.sql
011_create_store_builder_features.sql
008_create_sessions_auth_and_legacy_core.sql
012_create_admin_features.sql
013_create_event_outbox.sql
014_update_event_outbox_multi_region.sql
015_update_event_outbox_observability.sql
016_post_migration_patch_features.sql
017_performance_hardening_indexes.sql
018_orders_indexes.sql
019_event_outbox_indexes.sql
020_production_indexes.sql
021_production_constraints.sql
023_create_tenders_and_seed_columns.sql
025_create_banners.sql
"

run_db_bootstrap_async() {
  if [ "$RUN_DB_BOOTSTRAP_ON_START" = "0" ]; then
    echo "[entrypoint] RUN_DB_BOOTSTRAP_ON_START=0 — skipping DB wait + migrations."
    return
  fi

  if [ -z "$DB_URL" ]; then
    echo "[entrypoint] WARN: DATABASE_URL / ORDERS_DATABASE_URL not set — skipping DB wait and migrations."
    return
  fi

  (
    echo "[entrypoint] background DB bootstrap started."
    echo "[entrypoint] waiting up to ${DB_WAIT_SECONDS}s for PostgreSQL..."
    i=0
    while [ "$i" -lt "$DB_WAIT_SECONDS" ]; do
      if psql "$DB_URL" -c "SELECT 1" >/dev/null 2>&1; then
        echo "[entrypoint] PostgreSQL is reachable."
        break
      fi
      i=$((i + 1))
      sleep 1
    done

    if [ "$i" -ge "$DB_WAIT_SECONDS" ]; then
      echo "[entrypoint] WARN: Postgres not reachable after ${DB_WAIT_SECONDS}s — server is already running; DB-backed endpoints will fail until connectivity is restored."
      exit 0
    fi

    if [ -d /sql/migrations ]; then
      echo "[entrypoint] applying SQL migrations from /sql/migrations"
      for base in $MIGRATION_ORDER; do
        f="/sql/migrations/$base"
        if [ ! -f "$f" ]; then
          echo "[entrypoint] WARN: missing expected file $f — skipping."
          continue
        fi
        echo "[entrypoint] running $f"
        if ! psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"; then
          echo "[entrypoint] WARN: migration $base failed — continuing."
        fi
      done
    else
      echo "[entrypoint] WARN: /sql/migrations not found inside image — skipping migrations."
    fi
  ) &

  echo "[entrypoint] DB bootstrap is running in background; continuing server startup."
}

echo "[entrypoint] Starting server..."
run_db_bootstrap_async
if [ "$#" -gt 0 ]; then
  exec "$@"
else
  exec node dist/main.js
fi
