# Reglas de Rails para agentes (backend de ceiba)

> Adaptado de `ticket-harness/profiles/rails/rules.md` a ceiba: Rails 8 en modo API, PostgreSQL 18, Packwerk, todo en Docker.

## Comandos

- Todo dentro del contenedor `api` (directorio de trabajo `/app/backend`): `docker compose exec api bundle exec <herramienta>`;
  los `bin/*` (`bin/rails`, `bin/ci-*`) sin `bundle exec`. Atajos en el [`Makefile`](../../Makefile).
- Los specs con `-e RAILS_ENV=test`. Las rutas son relativas a `backend/`.
- Versiones fijadas en [`.tool-versions`](../../.tool-versions), los Dockerfiles y los lockfiles. Nunca "arregles" un comando
  actualizando la toolchain sin preguntar.

## Tiempo

- `Time.current`, `Date.current`, `Time.zone.now` o `ActiveSupport::TimeZone[branch.time_zone]`. Nunca `Time.now` /
  `Date.today` en código nuevo o modificado. Reemplazar uno existente es un cambio de comportamiento: lleva test.
- Congela el tiempo en specs (`travel_to` / `freeze_time`).

## Migraciones

- Genera con `docker compose exec api bin/rails g migration <Nombre>` o toma el timestamp de `date -u +%Y%m%d%H%M%S`. En un
  pack, mueve la migración generada sin cambiar su timestamp.
- Tablas tenant con `create_tenant_table` y `t.tenant_reference`, nunca a mano ([`09`](../architecture/09-data-conventions.md#tablas-tenant)).
- `strong_migrations` bloquea lo peligroso: índices `CONCURRENTLY` en su propia migración, `NOT VALID` y luego `VALIDATE` para
  restricciones sobre tablas existentes. Si algo no puede ser en línea, propón una alternativa; no lo fuerces con `safety_assured`.
- Agrega la columna, rellena por lotes (idempotente y reanudable) y luego restringe, en pasos de despliegue separados.
- Borrar o renombrar columnas o tablas es un despliegue en dos pasos (dejar de usarla, luego quitarla) y una decisión abierta
  para el desarrollador.
- `db/structure.sql` está versionado y CI exige que coincida con migrar desde cero. Conserva solo los cambios de tu migración;
  para regenerarlo sigue la receta de [`09`](../architecture/09-data-conventions.md#migraciones) (trampa de Rails 8.1 con
  `structure.sql`).
- No encadenes tareas de datos con tareas de esquema en el mismo comando: el rol de base (`app_owner`/`app_user`) se elige por
  proceso.
- Prueba migraciones solo contra bases locales desechables.

## RuboCop

- Base `rubocop-rails-omakase` + `rubocop-rails`, `rubocop-rspec`, `rubocop-factory_bot` y los cops propios `Ceiba/*`
  (`PackNamespace`, `TenantBypass`, `AccessPolicyRoles`, `AuthorizationSkips`, `DirectoryWrites`, `ModuleGateSkips`).
- Los cops `Ceiba/*` son reglas de arquitectura, no de estilo: nunca se desactivan con `rubocop:disable`. Si uno estorba, es una
  decisión para el desarrollador.
- `rubocop -A <archivo>` corrige el archivo ENTERO. Después, `git diff <archivo>` y revierte cada bloque ajeno. Prefiere
  `rubocop -A --only <Cop> <archivo>` o lint solo de tus archivos nuevos.

## RSpec

- Un comportamiento por ejemplo; `describe`/`context`/`it` descriptivos, con los contextos en español (`con`, `sin`, `cuando`,
  `al`, `si`). El primer ejemplo de una unidad nueva es el del rojo.
- `build` / `build_stubbed` salvo que el comportamiento consulte, recargue, valide, mute o destruya el registro. Sin ids fijos,
  sin `allow_any_instance_of`, sin `create` en `before(:all)`.
- Afirma resultados (`change { }`, valores de retorno, atributos persistidos, filas del outbox o de `audit_events`), no
  llamadas. Para fijar SQL generado: `ActiveSupport::Notifications.subscribe("sql.active_record")`.
- Endpoints: specs de rswag en `spec/api` o `packs/*/spec/api` (esquema estricto); el contrato se regenera con `bin/api-generate`.
- Jobs: idempotentes, argumentos serializables y probados contra una doble entrega.
- Los specs que tocan modelos tenant van dentro de `with_tenant(org) { ... }`; uno que no lo haga falla por diseño.

## Persistencia y transacciones

- Cambios locales de varias filas dentro de `ActiveRecord::Base.transaction`; nunca llamadas externas dentro. Los efectos
  externos salen por el outbox ([`06`](../architecture/06-events-and-jobs.md)).
- Escopa por organización toda relación tenant y verifica la pertenencia en búsquedas por id que manda el cliente.
- Cuidado con N+1: usa `includes`/`preload` y revisa el log de queries tras cambiar un listado.

## Packwerk

- El código de dominio vive en el pack dueño (`packs/platform/*` o `packs/modules/*`); otros packs solo usan su `app/public`.
- Entre módulos de negocio, solo eventos; nunca llamadas síncronas a otro módulo.
- Un pack nuevo se crea con `bin/rails g pack <capa>/<nombre>` ([`02`](../architecture/02-modular-monolith.md#generador-de-packs),
  [`playbooks/add-a-module`](../playbooks/add-a-module.md)).
- Antes de un push: `make ci s=backend-packs` además de los tests afectados.

## Antes de un push autorizado

`make ci` (o como mínimo las etapas `backend-lint`, `backend-packs`, `backend-migrations`, `backend-test`, `backend-security`,
`api-contract` y las de frontend si tocaste frontend) y reporta el resultado.
