# 09 — Convenciones de datos

> Decisiones: [ADR-0002](../adr/0002-postgresql-18.md), [ADR-0006](../adr/0006-uuidv7-como-clave-primaria.md), [ADR-0018](../adr/0018-integridad-de-agenda-en-bd.md). Hito: M0.04 (y se aplican en todos).

## Principio

**La base de datos defiende las invariantes que no pueden romperse.** Las validaciones de Rails dan buenos mensajes; las restricciones de PostgreSQL dan **garantías**. Las invariantes críticas tienen ambas.

## Identificadores

- PK `uuid` con default `uuidv7()` (PostgreSQL 18), configurado como default de los generadores de Rails (`primary_key_type: :uuid`).
- UUIDv7 es ordenado por tiempo: inserciones al final del índice (sin la fragmentación de v4), `ORDER BY id` ≈ orden de creación.
- Los IDs no son secuenciales ni adivinables: no revelan volumen y no permiten enumerar.
- Las FKs son `uuid`. Los nombres siguen la convención Rails (`company_id`).

## Tablas tenant

Toda tabla con datos de un cliente se crea con el helper:

```ruby
create_tenant_table :branches do |t|        # agrega organization_id NOT NULL + FK + índice
  t.tenant_reference :company                # agrega company_id + FK compuesta (organization_id, company_id)
  t.string :name, null: false
  t.string :time_zone, null: false, default: "America/Managua"
  t.timestamps
end
```

El helper:

1. Agrega `organization_id uuid NOT NULL` con FK a `organizations` y lo pone **primero** en los índices compuestos.
2. Agrega `UNIQUE (organization_id, id)` para que otras tablas puedan referenciarla con FK compuesta.
3. Crea la política RLS `tenant_isolation` (RLS deshabilitado hasta M4.03).
4. Registra la tabla en la lista de tablas tenant, que usan la suite de aislamiento y la migración de activación de RLS.

## Migraciones

- `strong_migrations` en CI: bloquea operaciones peligrosas sin una estrategia segura (índices sin `CONCURRENTLY`, cambios de tipo, `NOT NULL` sobre tablas grandes, etc.).
- Las migraciones de cada pack viven en `packs/<pack>/db/migrate`.
- PostgreSQL tiene **DDL transaccional**: una migración que falla se revierte completa. No se desactiva salvo en índices concurrentes (aislados en su propia migración).
- Migraciones de datos: separadas de las de esquema e idempotentes.
- `schema.rb` → **`structure.sql`**, porque se usan exclusion constraints, políticas RLS, triggers y extensiones que `schema.rb` no representa.

## Tiempo

| Regla | Detalle |
| --- | --- |
| Almacenamiento | `timestamptz` siempre, en UTC |
| Zona de referencia | La de la **sucursal** (`branches.time_zone`, IANA). Nunca la del servidor ni la del navegador |
| Fechas "de calendario" | Horarios semanales y ausencias de día completo: `time` / `date` locales a la sucursal, interpretados con su zona |
| Intervalos | `tstzrange` para los bloqueos de agenda (`blocks_from`, `blocks_to`) |
| DST | Nicaragua no usa DST, pero el motor de disponibilidad se prueba con zonas que sí lo usan |
| Rails | `config.time_zone = "UTC"`; conversiones explícitas con `ActiveSupport::TimeZone[branch.time_zone]` |

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
