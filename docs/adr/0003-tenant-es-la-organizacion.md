# ADR-0003: El tenant es la organización

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §3 (alcance del tenant) |

## Contexto

Hay tres niveles (organización, empresa, sucursal). Se debía elegir cuál es la frontera dura entre clientes de la plataforma.

## Decisión

El tenant (`acts_as_tenant`, RLS y la propagación a los jobs) es la **organización**. Empresa y sucursal son **alcances de autorización** que viven en `Current.context` y se verifican con Pundit. Una sola base de datos y un esquema compartido, con `organization_id` en toda tabla tenant.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Tenant = empresa | Aislamiento más fino | Rompe los reportes consolidados y a la persona que trabaja en varias empresas del grupo |
| Esquema por tenant (apartment) | Aislamiento fuerte | Migraciones N veces; mala experiencia con muchos tenants |
| BD por tenant | Aislamiento máximo | Operación inviable al inicio |

## Consecuencias

- **Positivas:** una sola frontera que probar; reportes de grupo posibles.
- **Negativas:** la separación entre empresas del mismo grupo depende de la autorización, que se cubre con la matriz de specs.
- **Obliga a:** suite de aislamiento de tenant y suite de matriz de autorización como suites **distintas**.

## Cuándo revisarla

Si un cliente exige BD dedicada: se extrae esa organización (ver 03-multi-tenancy).
