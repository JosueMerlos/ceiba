# ADR-0005: Row Level Security preparado desde el día 0 y activado antes de los pilotos

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Inconsistencia en `plans/`: "opcional" en citas §3 vs "descartado" en pendientes §4 |

## Contexto

La única barrera entre tenants era la capa de aplicación (`acts_as_tenant`). Un `unscoped`, un SQL crudo o un bug de una gema puede filtrar datos. Añadir RLS **después**, sobre decenas de tablas con datos, es caro y arriesgado.

## Decisión

Desde M0.04, toda tabla tenant nace con `organization_id`, FKs compuestas y una política RLS **creada pero deshabilitada**. `Tenancy.with_context` ejecuta `SET LOCAL app.organization_id` desde M0.05. **En M4.03** (antes de los pilotos) se habilita RLS en todas las tablas tenant, con un rol de aplicación sin `BYPASSRLS` que no es dueño de las tablas.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| RLS activo desde el día 0 | Máxima defensa desde el inicio | Fricción en consola, seeds y tests mientras el dominio aún cambia |
| Descartado | Lo más simple | Una sola barrera para el riesgo más grave del producto |

## Consecuencias

- **Positivas:** defensa en profundidad con un costo incremental bajo; activarlo es una migración.
- **Negativas:** el `SET LOCAL` requiere transacción; hay que administrar roles de BD distintos (aplicación, migraciones, bypass para back-office).
- **Obliga a:** helper `create_tenant_table`; suite de bypass de RLS en M4.03.

## Cuándo revisarla

Si el costo de rendimiento medido de las políticas fuera significativo (improbable con `organization_id` indexado).
