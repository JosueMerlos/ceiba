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
# Conexión: PG* si vienen definidas; si no, las variables del entorno de la app (CI) o el socket local (contenedor db).
export PGUSER="${PGUSER:-${POSTGRES_USER:-postgres}}"
[ -z "${DB_HOST:-}" ] || export PGHOST="${PGHOST:-$DB_HOST}"
[ -z "${POSTGRES_PASSWORD:-}" ] || export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
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
#    En template1 solo se fijan privilegios (no tiene objetos de usuario ni se le cambia el dueño).
#    Las bases con datos (ceiba_development) pasan al dueño correcto junto con TODO lo que el superusuario
#    haya creado en public: tablas, secuencias, vistas, vistas materializadas y funciones. Una vista o función
#    que siga siendo del superusuario se ejecuta con sus privilegios y se saltaría RLS.
#    Los nombres de base se leen línea a línea y se pasan como variable de psql (:"db" = identificador citado).
while IFS= read -r database; do
  [ -n "$database" ] || continue
  if [ "$database" != "template1" ]; then
    echo 'ALTER DATABASE :"db" OWNER TO app_owner;' | psql_run -v db="$database"
  fi
  PGDATABASE="$database" psql_run -v is_template="$([ "$database" = template1 ] && echo true || echo false)" <<'SQL'
-- El dueño de la base es dueño del esquema public (pg_database_owner); app_user solo lo usa.
GRANT USAGE ON SCHEMA public TO app_user;

-- Objetos existentes de public que aún no sean de app_owner (p. ej. creados antes de M0.04 por el superusuario).
-- Se omiten los miembros de extensiones (citext, btree_gist...), que gestiona la propia extensión.
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
      -- Fuera: miembros de extensiones ('e') y secuencias de serial/IDENTITY ('a', 'i'), que cambian de dueño con su
      -- tabla (ALTER SEQUENCE falla con "linked to table"). Las particiones (dependencia 'a' del padre) SÍ se
      -- reasignan: ALTER TABLE padre OWNER TO no recorre las particiones.
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

-- Tablas y secuencias FUTURAS que cree app_owner (las migraciones): accesibles para app_user sin otro GRANT.
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;
SQL
done < <(psql_run -At -c "SELECT datname FROM pg_database WHERE datallowconn AND datname <> 'postgres' ORDER BY 1")

# 3. pg_stat_statements (diagnóstico de rendimiento) NO es una extensión de esquema ni de migraciones: exige
#    superusuario y shared_preload_libraries. Se crea solo en la base de mantenimiento `postgres` (las
#    estadísticas son de todo el clúster) para que no aparezca en db/structure.sql. Solo se comprueba que la
#    extensión esté DISPONIBLE (paquete contrib instalado); la precarga (shared_preload_libraries) la pone
#    compose.yaml en desarrollo. Sin precarga la extensión se crea igual pero no recoge estadísticas (CI).
if [ "$(psql_run -At -c "SELECT count(*) FROM pg_available_extensions WHERE name = 'pg_stat_statements'")" = "1" ]; then
  psql_run -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements"
fi

echo "roles de base de datos listos (app_owner, app_user)"
