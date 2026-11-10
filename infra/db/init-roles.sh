#!/usr/bin/env bash
# Ceiba database roles.
#
#   app_owner  owns the database and all tables; used by migrations (db:migrate, db:prepare...).
#   app_user   used by the running application. Owns nothing, is NOT a superuser and does NOT have BYPASSRLS, so RLS
#              policies apply to it. DML only (SELECT/INSERT/UPDATE/DELETE).
#
# IDEMPOTENT: safe to run any number of times. Converges roles, passwords, owners and privileges.
# Runs as the cluster superuser (POSTGRES_USER) in three places:
#   1. `db` container, first boot: /docker-entrypoint-initdb.d (only runs on an EMPTY volume).
#   2. Existing volume (or after changing passwords): `make db-roles`.
#   3. CI (GitHub Actions postgres service, no initdb.d) and `bin/ci`.
#
# Variables: APP_OWNER_PASSWORD, APP_USER_PASSWORD (required) and the standard libpq ones (PGHOST, PGPORT, PGUSER,
# PGPASSWORD). Inside the container, without PGHOST, it uses the local socket.
set -euo pipefail

: "${APP_OWNER_PASSWORD:?falta APP_OWNER_PASSWORD}"
: "${APP_USER_PASSWORD:?falta APP_USER_PASSWORD}"
# Connection: PG* when set; otherwise the app's env vars (CI) or the local socket (db container).
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
[ -z "${DB_HOST:-}" ] || export PGHOST="${PGHOST:-$DB_HOST}"
[ -z "${POSTGRES_PASSWORD:-}" ] || export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
export PGDATABASE=postgres

psql_run() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# 1. Roles (cluster-wide). CREATEDB because app_owner runs db:create/db:drop in development and test.
psql_run -v owner_pw="$APP_OWNER_PASSWORD" -v user_pw="$APP_USER_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE app_owner' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') \gexec
SELECT 'CREATE ROLE app_user'  WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user')  \gexec
ALTER ROLE app_owner WITH LOGIN CREATEDB NOSUPERUSER NOCREATEROLE NOBYPASSRLS PASSWORD :'owner_pw';
ALTER ROLE app_user  WITH LOGIN NOCREATEDB NOSUPERUSER NOCREATEROLE NOBYPASSRLS PASSWORD :'user_pw';
SQL

# 2. Per-database privileges. `template1` is included on purpose: CREATE DATABASE copies its default privileges, so
#    databases created by `db:create` (e.g. ceiba_test) are born with app_user's GRANTs. In template1 only privileges are
#    set (no user objects, no owner change). Databases with data (ceiba_development) move to the right owner along with
#    EVERYTHING the superuser created in public: tables, sequences, views, materialized views and functions. A view or
#    function still owned by the superuser runs with its privileges and would bypass RLS.
#    Database names are read line by line and passed as a psql variable (:"db" = quoted identifier).
while IFS= read -r database; do
  [ -n "$database" ] || continue
  if [ "$database" != "template1" ]; then
    echo 'ALTER DATABASE :"db" OWNER TO app_owner;' | psql_run -v db="$database"
  fi
  PGDATABASE="$database" psql_run -v is_template="$([ "$database" = template1 ] && echo true || echo false)" <<'SQL'
-- The database owner owns the public schema (pg_database_owner); app_user only uses it.
GRANT USAGE ON SCHEMA public TO app_user;

-- Hand existing public objects not yet owned by app_owner (e.g. created earlier by the superuser) to app_owner.
-- Extension members (citext, btree_gist...) are skipped: the extension itself manages them.
SELECT NOT :is_template AS reassign \gset
\if :reassign
DO $$
DECLARE obj record;
BEGIN
  FOR obj IN
    SELECT format('ALTER %s %s OWNER TO app_owner',
                  CASE c.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' WHEN 'S' THEN 'SEQUENCE'
                                 WHEN 'f' THEN 'FOREIGN TABLE' ELSE 'TABLE' END,
                  c.oid::regclass) AS ddl
    FROM pg_class c
    WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
      AND pg_get_userbyid(c.relowner) <> 'app_owner'
      -- Skip extension members ('e') and serial/IDENTITY sequences ('a', 'i'): they follow their table's owner
      -- (ALTER SEQUENCE fails with "linked to table"). Partitions are reassigned: ALTER TABLE parent OWNER TO
      -- does not cascade to them.
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = c.oid AND d.classid = 'pg_class'::regclass
                      AND (d.deptype = 'e' OR (c.relkind = 'S' AND d.deptype IN ('a', 'i'))))
    UNION ALL
    SELECT format('ALTER %s %s OWNER TO app_owner', CASE p.prokind WHEN 'p' THEN 'PROCEDURE' ELSE 'FUNCTION' END, p.oid::regprocedure)
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.prokind IN ('f', 'p')
      AND pg_get_userbyid(p.proowner) <> 'app_owner'
      AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.objid = p.oid AND d.classid = 'pg_proc'::regclass AND d.deptype = 'e')
  LOOP
    EXECUTE obj.ddl;
  END LOOP;
END $$;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
\endif

-- FUTURE tables and sequences created by app_owner (migrations) are accessible to app_user without another GRANT.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;
SQL
done < <(psql_run -At -c "SELECT datname FROM pg_database WHERE datallowconn AND datname <> 'postgres' ORDER BY 1")

# 3. pg_stat_statements is NOT a schema or migration extension: it needs a superuser and shared_preload_libraries. It is
#    created only in the `postgres` maintenance database (stats are cluster-wide) so it stays out of db/structure.sql.
#    It must merely be AVAILABLE (contrib package installed); compose.yaml sets the preload in development. Without the
#    preload the extension is still created but collects no statistics (CI).
if [ "$(psql_run -At -c "SELECT count(*) FROM pg_available_extensions WHERE name = 'pg_stat_statements'")" = "1" ]; then
  psql_run -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
fi

echo "roles de base de datos listos (app_owner, app_user)"
