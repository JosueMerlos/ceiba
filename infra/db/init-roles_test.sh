#!/usr/bin/env bash
# Prueba de infra/db/init-roles.sh en una base efímera: como superusuario se crean una tabla con IDENTITY, una
# con serial, una vista, una vista materializada, una función y una tabla particionada con partición; el script
# se ejecuta DOS veces (debe ser idempotente) y todo debe terminar siendo de app_owner.
#
# Variables: las mismas que init-roles.sh (APP_*_PASSWORD, PG*/POSTGRES_*/DB_HOST) y, opcional, INIT_ROLES
# (ruta del script; por defecto el contiguo). bin/ci lo corre dentro del contenedor db:
#   docker compose exec -T db env INIT_ROLES=/docker-entrypoint-initdb.d/10-roles.sh bash -s < infra/db/init-roles_test.sh
set -euo pipefail

init_roles="${INIT_ROLES:-$(dirname "${BASH_SOURCE[0]}")/init-roles.sh}"
database="ceiba_roles_probe"
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
[ -z "${DB_HOST:-}" ] || export PGHOST="${PGHOST:-$DB_HOST}"
[ -z "${POSTGRES_PASSWORD:-}" ] || export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"

psql_super() { PGDATABASE="${PGDATABASE:-postgres}" psql -X -q -v ON_ERROR_STOP=1 "$@"; }
cleanup() { PGDATABASE=postgres psql_super -c "DROP DATABASE IF EXISTS $database WITH (FORCE)" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

PGDATABASE=postgres psql_super -c "CREATE DATABASE $database"
PGDATABASE=$database psql_super <<'SQL'
CREATE TABLE identity_things (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name text);
CREATE TABLE serial_things (id serial PRIMARY KEY, name text);
CREATE VIEW things_view AS SELECT id, name FROM identity_things;
CREATE MATERIALIZED VIEW things_matview AS SELECT id, name FROM serial_things;
CREATE FUNCTION add_one(integer) RETURNS integer LANGUAGE sql AS 'SELECT $1 + 1';
CREATE TABLE events (id bigint GENERATED ALWAYS AS IDENTITY, at date NOT NULL) PARTITION BY RANGE (at);
CREATE TABLE events_2026 PARTITION OF events FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');
SQL

for run in 1 2; do
  echo "init-roles.sh, ejecución $run"
  "$init_roles" >/dev/null || { echo "FALLA init-roles.sh en la ejecución $run" >&2; exit 1; }
done

foreign_owned="$(PGDATABASE=$database psql_super -At <<'SQL'
SELECT c.relname FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r', 'p', 'v', 'm', 'S') AND pg_get_userbyid(c.relowner) <> 'app_owner'
UNION ALL
SELECT p.proname FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND pg_get_userbyid(p.proowner) <> 'app_owner'
SQL
)"
if [ -n "$foreign_owned" ]; then
  echo "FALLA objetos que no son de app_owner:" >&2
  echo "$foreign_owned" >&2
  exit 1
fi
echo "ok    init-roles.sh es idempotente y deja todo en app_owner (identity, serial, vistas, función, particiones)"
