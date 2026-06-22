-- ============================================================
-- Runs once, only when the Postgres data volume is first created
-- (docker-entrypoint-initdb.d). Creates the PROD and QA databases.
--
-- The bm_app role is created by the container from POSTGRES_USER /
-- POSTGRES_PASSWORD before this script runs, so we only create the
-- databases and grant privileges here.
--
-- To re-run after changing this file you must reset the volume:
--   docker compose down -v   (DELETES ALL DATA)
-- ============================================================

-- PROD database
CREATE DATABASE bm_backend OWNER bm_app;

-- QA database
CREATE DATABASE bm_qa OWNER bm_app;

GRANT ALL PRIVILEGES ON DATABASE bm_backend TO bm_app;
GRANT ALL PRIVILEGES ON DATABASE bm_qa TO bm_app;
