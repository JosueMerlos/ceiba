# ADR-0009: Sidekiq + Redis para jobs, con outbox transaccional propio

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | Sesión de cimientos (se evaluó Solid Queue) |

## Contexto

El plan exige "encolar después del commit (outbox)" para no perder eventos. Con una cola en Redis, guardar en PostgreSQL y encolar no son atómicos.

## Decisión

Se mantiene **Sidekiq + Redis**. Los eventos de dominio se escriben en `outbox_events` **en la misma transacción** del caso de uso; un relay los publica a Sidekiq. Los consumidores son idempotentes (`processed_events`).

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Solid Queue en la misma BD | Encolar dentro de la transacción ya es un outbox; un servicio menos | Menor rendimiento y ecosistema; el usuario prefiere Sidekiq |
| Sidekiq sin outbox | Simple | Pierde eventos si Redis falla tras el commit |

## Consecuencias

- **Positivas:** Sidekiq maduro, panel y reintentos; entrega garantizada al menos una vez.
- **Negativas:** Redis es infraestructura crítica; más piezas (relay, purgas).
- **Obliga a:** M0.10 (outbox, relay, idempotencia), alertas por outbox atrasado y jobs que reciben `organization_id`.

## Cuándo revisarla

Si Redis se vuelve una carga operativa desproporcionada; Solid Queue es la salida natural.
