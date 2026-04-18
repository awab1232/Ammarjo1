-- Legacy docker-init bootstrap used psql-only commands (\i /schema/...).
-- Those paths are not bundled in the Railway/Docker image; schema is owned by
-- numbered migrations 001+ instead. Intentional no-op for apply-all-sql.cjs (postgres JS).

SELECT 1;
