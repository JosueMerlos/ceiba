#!/usr/bin/env bash
# Roles de base de datos de Ceiba (M0.04, ADR-0005, docs/architecture/03-multi-tenancy.md).
#
#   app_owner  dueño de la base y de todas las tablas; lo usan las migraciones (db:migrate, db:prepare...).
#   app_user   lo usa la aplicación en ejecución. NO es dueño de nada, NO es superusuario y NO tiene
#              BYPASSRLS: por eso las políticas RLS (M4.03) le aplican. Solo DML (SELECT/INSERT/UPDATE/DELETE).
#
# IDEMPOTENTE: se puede correr las veces que haga falta. Converge roles, contraseñas, propietarios y privilegios.
# Se ejecuta con el superusuario del clúster (POSTGRES_USER) en tres sitios:
#   1. Contenedor `db`, primera vez: /docker-entrypoint-initdb.d (solo corre con el volumen VACÍO).
#   2. Volumen existente (o tras cambiar contraseñas): `make db-roles`.
#   3. CI (servicio postgres de GitHub Actions, sin initdb.d) y `bin/ci`.
#
# Variables: APP_OWNER_PASSWORD, APP_USER_PASSWORD (obligatorias) y las estándar de libpq
# (PGHOST, PGPORT, PGUSER, PGPASSWORD). Dentro del contenedor, sin PGHOST, usa el socket local.
set -euo pipefail

: "${APP_OWNER_PASSWORD:?falta APP_OWNER_PASSWORD}"
: "${APP_USER_PASSWORD:?falta APP_USER_PASSWORD}"
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
export PGDATABASE=postgres

psql_run() { psql -X -q -v ON_ERROR_STOP=1 "$@"; }

# 1. Roles (cluster-wide). CREATEDB: db:create/db:drop en desarrollo y test los ejecuta app_owner.
psql_run -v owner_pw="$APP_OWNER_PASSWORD" -v user_pw="$APP_USER_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE app_owner' WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') \gexec
SELECT 'CREATE ROLE app_user'  WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user')  \gexec
ALTER ROLE app_owner WITH LOGIN CREATEDB NOSUPERUSER NOCREATEROLE NOBYPASSRLS PASSWORD :'owner_pw';
ALTER ROLE app_user  WITH LOGIN NOCREATEDB NOSUPERUSER NOCREATEROLE NOBYPASSRLS PASSWORD :'user_pw';
SQL

# 2. Privilegios por base. `template1` va incluida a propósito: CREATE DATABASE copia sus privilegios por
#    defecto, así las bases que crea `db:create` (p. ej. ceiba_test) nacen ya con los GRANT de app_user.
#    Las bases con datos (ceiba_development) pasan al dueño correcto y se regrantan las tablas existentes.
databases=$(psql_run -At -c "SELECT datname FROM pg_database WHERE datallowconn AND datname <> 'postgres'")
for database in $databases; do
  if [ "$database" != "template1" ]; then
    psql_run -c "ALTER DATABASE \"$database\" OWNER TO app_owner"
  fi
  PGDATABASE="$database" psql_run <<'SQL'
-- El dueño de la base es dueño del esquema public (pg_database_owner); app_user solo lo usa.
GRANT USAGE ON SCHEMA public TO app_user;

-- Tablas existentes que aún no sean de app_owner (p. ej. creadas antes de M0.04 por el superusuario).
DO $$
DECLARE obj record;
BEGIN
  FOR obj IN SELECT format('%I.%I', schemaname, tablename) AS name FROM pg_tables
             WHERE schemaname = 'public' AND tableowner <> 'app_owner' LOOP
    EXECUTE format('ALTER TABLE %s OWNER TO app_owner', obj.name);
  END LOOP;
  FOR obj IN SELECT format('%I.%I', sequence_schema, sequence_name) AS name FROM information_schema.sequences
             WHERE sequence_schema = 'public' LOOP
    EXECUTE format('ALTER SEQUENCE %s OWNER TO app_owner', obj.name);
  END LOOP;
END $$;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Tablas y secuencias FUTURAS que cree app_owner (las migraciones): accesibles para app_user sin otro GRANT.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;
SQL
done

# 3. pg_stat_statements (diagnóstico de rendimiento) NO es una extensión de esquema ni de migraciones: exige
#    superusuario y shared_preload_libraries. Se crea solo en la base de mantenimiento `postgres` (las
#    estadísticas son de todo el clúster) para que no aparezca en db/structure.sql. Si el servidor no la
#    tiene precargada, se omite sin fallar (CI).
if [ "$(psql_run -At -c "SELECT count(*) FROM pg_available_extensions WHERE name = 'pg_stat_statements'")" = "1" ]; then
  psql_run -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
fi

echo "roles de base de datos listos (app_owner, app_user)"
