\echo [docker-init] Applying orders-api schemas...
\set ON_ERROR_STOP on

\i /schema/users_schema.sql
\i /schema/orders_schema.sql
\i /schema/store_product_domain_schema.sql
\i /schema/catalog_products_schema.sql
\i /schema/wholesale_schema.sql
\i /schema/service_requests_schema.sql
\i /schema/ratings_reviews_schema.sql
\i /schema/hybrid_store_builder_schema.sql
\i /schema/event_outbox_schema.sql
\i /schema/event_outbox_multi_region_migration.sql
\i /schema/event_outbox_observability_migration.sql
\i /schema/event_outbox_indexes_performance.sql
\i /schema/orders_indexes_migration.sql
\i /schema/phase6_performance_hardening.sql
\i /schema/post_migration_patch.sql
\i /schema/cart_and_user_notifications_schema.sql
\i /schema/admin_panel_schema.sql

\echo [docker-init] All schema files applied.
