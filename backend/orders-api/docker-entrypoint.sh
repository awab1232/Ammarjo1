#!/bin/sh
set -eu

DB_URL="${DATABASE_URL:-${ORDERS_DATABASE_URL:-}}"
if [ -z "$DB_URL" ]; then
  echo "docker-entrypoint: DATABASE_URL or ORDERS_DATABASE_URL is required"
  exit 1
fi

echo "docker-entrypoint: waiting for PostgreSQL..."
until psql "$DB_URL" -c "SELECT 1" >/dev/null 2>&1; do
  sleep 1
done

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
# 022_apply_schemas_bootstrap.sql is not run here: it only \i includes files under
# /schema (see migration file). Those paths are for a host-mounted database/
# bundle; the numbered migrations above already apply the same schema.

if [ -d /sql/migrations ]; then
  echo "docker-entrypoint: applying SQL migrations from /sql/migrations"
  for base in $MIGRATION_ORDER; do
    f="/sql/migrations/$base"
    if [ ! -f "$f" ]; then
      echo "docker-entrypoint: warning: missing expected file $f"
      continue
    fi
    echo "docker-entrypoint: running $f"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$f"
  done
else
  echo "docker-entrypoint: warning: /sql/migrations not found"
fi

exec "$@"
