# 09 — Convenciones de datos

> Decisiones: [ADR-0002](../adr/0002-postgresql-18.md), [ADR-0005](../adr/0005-rls-preparado-activado-en-piloto.md), [ADR-0006](../adr/0006-uuidv7-como-clave-primaria.md), [ADR-0018](../adr/0018-integridad-de-agenda-en-bd.md). Hito: M0.04 (y se aplican en todos). Código: pack `platform/database` (`backend/packs/platform/database`).

## Principio

**La base de datos defiende las invariantes que no pueden romperse.** Las validaciones de Rails dan buenos mensajes; las restricciones de PostgreSQL dan **garantías**. Las invariantes críticas tienen ambas.

## Identificadores

- PK `uuid` con default `uuidv7()` (PostgreSQL 18), configurado como default de los generadores de Rails (`config.generators { |g| g.orm :active_record, primary_key_type: :uuid }`, en `config/application.rb`): `rails g model Foo` genera `create_table :foos, id: :uuid` y las referencias como `uuid`.
- Rails pone `gen_random_uuid()` (UUIDv4) como default de `id: :uuid`; `Database::UuidPrimaryKey` (prepend en `PostgreSQL::TableDefinition#primary_key`) lo cambia a `uuidv7()` salvo que la migración pida otro `default:` explícito. Así la migración generada es correcta sin recordar nada y `db/structure.sql` muestra `id uuid DEFAULT uuidv7() NOT NULL`.
- UUIDv7 es ordenado por tiempo: inserciones al final del índice (sin la fragmentación de v4), `ORDER BY id` ≈ orden de creación.
- Los IDs no son secuenciales ni adivinables: no revelan volumen y no permiten enumerar.
- Las FKs son `uuid`. Los nombres siguen la convención Rails (`company_id`).

## Tablas tenant

Toda tabla con datos de un cliente se crea con el helper:

```ruby
create_tenant_table :branches do |t|        # agrega organization_id NOT NULL + FK + UNIQUE + política RLS
  t.tenant_reference :company                # agrega company_id + FK compuesta (organization_id, company_id)
  t.string :name, null: false
  t.string :time_zone, null: false, default: "America/Managua"
  t.timestamps
end
```

### Firma real de los helpers (`Database::SchemaStatements`, `Database::TableDefinition`)

Se instalan en el adaptador de PostgreSQL (initializer del pack `platform/database`), así que están disponibles en cualquier migración de cualquier pack. Son reversibles en migraciones `change` (`Database::CommandRecorder`).

| Helper | Firma | Qué hace |
| --- | --- | --- |
| `create_tenant_table` | `create_tenant_table(table_name, on_delete: :restrict, **create_table_options) { \|t\| ... }` | Ver abajo. No acepta `id:` distinto de uuid ni `organization_id` declarado a mano ni la tabla `organizations` (es la raíz del tenant: se crea con `create_table`) |
| `t.tenant_reference` | `t.tenant_reference(name, null: false, to_table: nil, index: true, foreign_key: true, on_delete: :restrict)` | Solo dentro de `create_tenant_table`. `company_id uuid NOT NULL`, FK compuesta `fk_<tabla>_<name>` `(organization_id, company_id) → <to_table \|\| name.pluralize>(organization_id, id)` e índice `(organization_id, company_id)` |
| `enable_tenant_rls` | `enable_tenant_rls(table_name, force: false)` | `ENABLE ROW LEVEL SECURITY` (y `FORCE` si `force: true`). Lo usa M4.03. Solo para tablas creadas con `create_tenant_table` |
| `disable_tenant_rls` | `disable_tenant_rls(table_name)` | Inversa de la anterior |
| `Database::TenantTables` | `.names(connection)`, `.rls_enabled(connection)`, `.tenant?(table, connection)`, `.inconsistencies(connection, exempt: [])` | El **registro** de tablas tenant, para la suite de aislamiento (M0.05) y la migración de M4.03 |

`create_tenant_table`:

1. Crea la tabla con `id uuid DEFAULT uuidv7()` y `organization_id uuid NOT NULL` (primera columna tras `id`) con FK `fk_<tabla>_organization` a `organizations`.
2. Agrega `UNIQUE (organization_id, id)` (`uq_<tabla>_organization_id_id`) para que otras tablas puedan referenciarla con FK compuesta. Ese índice único también sirve como índice por organización (prefijo `organization_id`), por eso no se crea otro.
3. Crea la política RLS `tenant_isolation` (`FOR ALL`, `USING` y `WITH CHECK`) **sin** `ENABLE ROW LEVEL SECURITY` (se activa en M4.03).
4. **Registro:** una tabla es tenant si tiene la política `tenant_isolation`. El registro se **deriva del catálogo** (`pg_policies`), no vive en una tabla propia: no puede desincronizarse, viaja en `db/structure.sql` y no necesita migraciones.

La condición de la política difiere en un detalle de la del doc 03: usa `NULLIF(current_setting('app.organization_id', true), '')::uuid`. Tras un `SET LOCAL app.organization_id` previo, al terminar la transacción el setting queda como cadena vacía (no `NULL`) y `''::uuid` lanzaría un error en lugar de devolver cero filas; con `NULLIF` una conexión sin contexto no ve nada y no falla (`packs/platform/database/spec/database/tenant_rls_spec.rb`).

**`on_delete`:** `:restrict` por defecto (el más seguro: borrar una organización o una empresa con datos es una operación explícita, offboarding en P3, no un efecto lateral) o `:cascade`; se aplica a la FK a `organizations` (`create_tenant_table`) y a la FK compuesta (`tenant_reference`). `:nullify` se **rechaza** con un mensaje claro: anularía `organization_id`, que es `NOT NULL` y parte de la FK compuesta. Los nombres de restricción generados (`fk_<tabla>_organization`, `uq_<tabla>_organization_id_id`, `fk_<tabla>_<ref>`) se validan: más de 63 caracteres lanza `ArgumentError` en vez de que PostgreSQL los trunque en silencio.

**Guardián de consistencia:** `packs/platform/database/spec/database/tenant_tables_consistency_spec.rb` exige que las tablas con columna `organization_id` sean exactamente `Database::TenantTables.names` (en ambos sentidos; exenciones solo justificadas, hoy ninguna). Una tabla creada con `create_table` normal + `organization_id` rompe el spec.

`organizations`, `companies` y `branches` existen desde M0.05 (pack `platform/tenancy`). Los specs de las convenciones crean sus tablas de prueba (incluida una `organizations` mínima) **solo dentro del spec**, en un esquema `tenant_probe` dentro de una transacción de dueño que se revierte (`spec/support/tenant_schema_helpers.rb`), para no chocar con las tablas reales; no hay tablas de prueba en migraciones. Nota de M0.05: una FK `ON DELETE RESTRICT` falla con `PG::RestrictViolation` (`ActiveRecord::StatementInvalid`), no con `InvalidForeignKey`; `NO ACTION` sí daría `InvalidForeignKey`.

## Roles de base de datos

| Rol | Quién lo usa | Permisos |
| --- | --- | --- |
| `app_owner` | Las tareas `db:*` (create, drop, migrate, rollback, schema:load, prepare, seeds ejecutados vía `db:*`) | Dueño de la base y de todas las tablas; `CREATEDB`; sin superusuario ni `BYPASSRLS` |
| `app_user` | La aplicación en ejecución: servidor, worker, consola, `rspec` | Solo `SELECT/INSERT/UPDATE/DELETE` y uso de secuencias; **no es dueño de nada**, sin DDL, sin superusuario, **sin `BYPASSRLS`** |

- **Selección del rol (`config/database.yml` + `config/db_roles.rb`): `app_user` por defecto y una ALLOWLIST explícita de tareas de esquema que corren como `app_owner`.** Servidor, worker, consola, `runner`, `rspec`, `db:seed` y cualquier tarea no listada conectan como `app_user`. `DB_ROLE=owner|user` sobrescribe el rol. Un `bin/rails db:migrate` sin variables funciona porque está en la allowlist. Contraseñas: `APP_OWNER_PASSWORD`, `APP_USER_PASSWORD` (defaults de desarrollo en `compose.yaml`, valores efímeros en `ci.yml`).

  Allowlist (`DbRoles::OWNER_TASKS`, y sus variantes `:primary`): `db:create`, `db:create:all`, `db:drop`, `db:drop:all`, `db:purge`, `db:purge:all`, `db:migrate`, `db:migrate:up`, `db:migrate:down`, `db:migrate:redo`, `db:migrate:reset`, `db:rollback`, `db:forward`, `db:reset`, `db:reset:all`, `db:setup`, `db:setup:all`, `db:prepare`, `db:schema:load`, `db:schema:dump`, `db:structure:load`, `db:structure:dump`, `db:environment:set`, `db:test:prepare`, `db:test:load`, `db:test:load_schema`, `db:test:load_structure`, `db:test:purge`. **Fuera a propósito:** `db:seed`, `db:seed:replant`, `db:fixtures:load`, `db:truncate_all` (datos), `db:migrate:status`, `db:version`, `db:abort_if_pending_migrations` (lectura). **Regla:** una tarea propia que cambie el esquema o la base debe **añadirse a `OWNER_TASKS` con revisión**; por omisión, toda tarea corre sin privilegios de dueño (un olvido produce un `permission denied`, nunca privilegios de más).
- **Los seeds siempre corren como `app_user`**, incluso dentro de `db:prepare`/`db:setup`/`db:reset` (que corren como `app_owner`): `config/initializers/seed_role.rb` reconecta como `app_user` antes de `load_seed` y restaura la conexión después. Así los datos iniciales pasan por las mismas políticas RLS que la aplicación.
- **No encadenes tareas de datos con tareas de esquema en el mismo comando** (`bin/rails db:seed db:migrate`): la selección de rol se hace por proceso y basta una tarea de la allowlist para que TODAS corran como `app_owner`. Ejecútalas en comandos separados. `db:seed:replant` y `db:truncate_all` (que truncan; `app_user` no puede) requieren `DB_ROLE=owner` explícito.
- **Esquema de test:** `spec/support/test_schema.rb` reemplaza a `maintain_test_schema!` (que recargaría el esquema en proceso con la conexión de la suite, `app_user`, sin DDL). Con migraciones pendientes **aborta** pidiendo `make migrate` (migrar vuelca `db/structure.sql`, que está versionado, y la suite no debe reescribirlo en silencio); si solo `structure.sql` cambió, lanza `db:test:prepare` en un **subproceso** con `DB_ROLE=owner`; la suite sigue como `app_user`.
- `app_user` **no tiene `TRUNCATE` ni puede `DISABLE TRIGGER`** (no es dueño): las estrategias de limpieza por truncado (`database_cleaner` con `:truncation`, `use_transactional_fixtures = false`, `ActiveRecord::FixtureSet` con deshabilitar triggers) no funcionan con él. La suite usa fixtures transaccionales; si algún día hiciera falta truncar, se hace con `OwnerConnection`, no concediendo el privilegio.
- Los crea `infra/db/init-roles.sh`, **idempotente** (converge roles, contraseñas, propietarios y privilegios): (1) el contenedor `db` lo ejecuta desde `docker-entrypoint-initdb.d`, pero PostgreSQL **solo corre initdb con el volumen vacío**; (2) con un volumen existente se aplica con **`make db-roles`** (`make up` también lo ejecuta antes de levantar la API); (3) en CI el servicio `postgres` de GitHub Actions no tiene `initdb.d`, así que es un paso del workflow, y `bin/ci` lo ejecuta antes de las etapas con base de datos.
- Privilegios de tablas futuras: `ALTER DEFAULT PRIVILEGES FOR ROLE app_owner ... GRANT ... TO app_user`. Los privilegios por defecto son **por base de datos**: el script también los fija en `template1`, de modo que cualquier base creada con `db:create` (p. ej. `ceiba_test`) nace con ellos. `structure.sql` se vuelca con `--no-privileges --no-owner`, así que **no** transporta GRANT ni propietarios: al cargarlo como `app_owner` las tablas quedan suyas y los privilegios por defecto hacen el resto.
- Un rol sin `BYPASSRLS` y que no es dueño es lo que hace que la RLS de M4.03 le aplique a la aplicación (el dueño ignora RLS salvo `FORCE`). Los caminos privilegiados (back-office) usarán un tercer rol con `BYPASSRLS`, fuera de M0.04.
- Los specs que necesitan DDL (crear tablas de prueba) usan `OwnerConnection` (`spec/support/owner_connection.rb`): una conexión de dueño aparte, dentro de una transacción que siempre se revierte.

## Migraciones

- `strong_migrations` (2.8.0, `config/initializers/strong_migrations.rb`) bloquea operaciones peligrosas sin una estrategia segura (índices sin `CONCURRENTLY`, cambios de tipo, `NOT NULL` sobre tablas grandes, etc.). Configuración: `target_version = 18`, `lock_timeout = 10 s` (con 3 reintentos cada 5 s), `statement_timeout = 1 h`, `auto_analyze`. Está activo en desarrollo, test y CI: `spec/config/strong_migrations_spec.rb` demuestra que un `add_index` sin `algorithm: :concurrently` es rechazado y la etapa `backend-migrations` falla con cualquier migración peligrosa. Nota: strong_migrations considera segura una operación sobre una tabla **creada en la misma migración**.
- Las migraciones de cada pack viven en `packs/<pack>/db/migrate`. Las extensiones (`btree_gist`, `citext`) las habilita una migración de `platform/database`.
- PostgreSQL tiene **DDL transaccional**: una migración que falla se revierte completa. No se desactiva salvo en índices concurrentes (aislados en su propia migración).
- Migraciones de datos: separadas de las de esquema e idempotentes.
- `schema.rb` → **`structure.sql`** (`config.active_record.schema_format = :sql`), porque se usan exclusion constraints, políticas RLS, triggers y extensiones que `schema.rb` no representa. Requiere `pg_dump` de la **misma versión mayor que el servidor**: la imagen del api **y los jobs `backend-migrations`/`backend-test` de CI** instalan `postgresql-client-18` desde PGDG (Debian trixie y el runner ubuntu-24.04 traen el 17 y el 16, y `pg_dump` se niega a volcar un servidor 18). `infra/scripts/check-versions.sh` verifica que el cliente instalado coincida con la versión mayor de `postgres` en `.tool-versions`.
- **CI de migraciones** (`backend/bin/ci-migrations`, job `backend-migrations`, `bin/ci backend-migrations`): migra desde una base vacía, revierte la última migración y vuelve a migrar, y en ambos puntos exige que `db/structure.sql` quede **idéntico** al versionado (migración sin volcar = fallo); por último carga `structure.sql` en una base vacía y comprueba extensiones, rol `app_user` y que no queden migraciones pendientes. `spec/db/structure_sql_spec.rb` prueba además, sobre una copia de la app con tablas tenant reales, que el volcado incluye extensiones, políticas `tenant_isolation`, FKs compuestas y `UNIQUE (organization_id, id)`, que es determinista y que se carga en una base vacía.

## Tiempo

| Regla | Detalle |
| --- | --- |
| Almacenamiento | `timestamptz` siempre, en UTC |
| Zona de referencia | La de la **sucursal** (`branches.time_zone`, IANA). Nunca la del servidor ni la del navegador |
| Fechas "de calendario" | Horarios semanales y ausencias de día completo: `time` / `date` locales a la sucursal, interpretados con su zona |
| Intervalos | `tstzrange` para los bloqueos de agenda (`blocks_from`, `blocks_to`) |
| DST | Nicaragua no usa DST, pero el motor de disponibilidad se prueba con zonas que sí lo usan |
| Rails | `config.time_zone = "UTC"` y `config.active_record.default_timezone = :utc`; conversiones explícitas con `ActiveSupport::TimeZone[branch.time_zone]` |

## Idioma (i18n)

`rails-i18n` 8.1.0; `config.i18n.default_locale = :"es-NI"` y `available_locales = [:"es-NI", :en]` (`en` solo como respaldo técnico). Los textos del backend viven en `config/locales` del pack que los usa (el generador de packs crea `es-NI.yml`). Cubierto por `spec/config/i18n_spec.rb`.

## Dinero

- Columnas `*_minor` (`bigint`, unidades menores: centavos) + `currency` (`char(3)`, ISO 4217).
- Moneda por **empresa**: `NIO` o `USD` hoy; validada contra una lista permitida.
- Los precios congelados (en `appointment_services`) guardan su moneda: un cambio de moneda de la empresa no reinterpreta el historial.
- Sin floats en ningún lado (ni en la API, ni en JS: `amount_minor` es entero).
- Formato con `Intl.NumberFormat("es-NI", { style: "currency", currency })` en el front y `money` / `I18n` en el back.

## Teléfonos, correos y nombres

- Teléfonos en **E.164** (`+50588887777`), normalizados al guardar con `phonelib` (región por defecto `NI`). El teléfono es el identificador práctico del cliente final.
- Correos normalizados (minúsculas y sin espacios).
- Nombres: un `full_name` libre; no se impone nombre y apellido separados.

## Datos personales (PII)

- **Active Record Encryption** para PII sensible del cliente final: teléfono y correo con cifrado **determinista** (permite buscar por igualdad), y notas con cifrado no determinista.
- Claves de cifrado en Rails credentials / Kamal secrets, con un runbook de rotación.
- `filter_parameters` cubre teléfono, correo, token y contraseña: no aparecen en los logs.
- Los datos de salud **no** viven en `appointments`: las notas de la cita son operativas ("llega 5 min tarde"), no clínicas.

## Borrado

| Caso | Estrategia |
| --- | --- |
| Catálogos (servicios, profesionales, recursos) | **Archivado** (`archived_at`): no se borran porque el historial de citas los referencia |
| Citas | Nunca se borran; cambian de estado |
| Cliente que ejerce el derecho de supresión (Ley 787) | **Anonimización**: se borran o reemplazan los campos personales y se conservan los conteos y el historial anónimo |
| Organización que se va (offboarding) | Exportación + periodo de retención + borrado físico por `organization_id` (P3) |
| Auditoría | Append-only; nunca se borra ([ADR-0022](../adr/0022-auditoria-append-only-e-idempotencia.md)) |

No se usa una gema de soft delete global (`paranoia` y similares): esconden filas en todas las consultas y generan bugs sutiles. El archivado es explícito por modelo.

## Índices: reglas

- Todo índice compuesto de una tabla tenant empieza por `organization_id` cuando la consulta típica filtra por tenant.
- Índices de agenda: `(organization_id, branch_id, starts_at)` y `(organization_id, professional_id, starts_at)`.
- Índices parciales para estados activos (`WHERE status IN ('scheduled','confirmed')`).
- Toda FK lleva índice.
- Se revisa con `EXPLAIN` cualquier consulta del motor de disponibilidad y de la agenda antes de cerrar su hito.

## Extensiones de PostgreSQL

| Extensión | Para qué |
| --- | --- |
| `btree_gist` | Exclusion constraints que combinan `=` y `&&` |
| `citext` | Correos y slugs sin distinguir mayúsculas y minúsculas |
| `pg_stat_statements` | Diagnóstico de rendimiento (staging y producción) |

`btree_gist` y `citext` son extensiones *trusted* de PostgreSQL: las habilita la migración `EnableCoreExtensions` ejecutándose como `app_owner`, sin superusuario, y aparecen en `db/structure.sql`. `pg_stat_statements` **no es una extensión de migraciones**: exige superusuario y `shared_preload_libraries`. Se precarga en el contenedor `db` de desarrollo (`compose.yaml`) y `infra/db/init-roles.sh` la crea solo en la base de mantenimiento `postgres` (las estadísticas son de todo el clúster), por lo que no entra en `structure.sql`. En staging y producción la habilita operaciones (M4.04).
