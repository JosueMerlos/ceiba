# ADR-0019: Reprogramar crea una cita nueva, con bloqueo y transición condicionada

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §4 (estados) |

## Decisión

`Appointments::Reschedule` bloquea la cita original (`SELECT … FOR UPDATE`), la pasa a `rescheduled` con `WHERE status IN ('scheduled','confirmed')` verificando las filas afectadas, y crea la nueva vía `Appointments::Book` con `rescheduled_from_id`. Si dos personas reprograman a la vez, la segunda recibe `409`. Las transiciones de estado viven en un servicio de dominio, nunca en controladores.

Flujo: `scheduled → confirmed → checked_in → completed`; estados alternos: `cancelled`, `no_show`, `rescheduled`.

## Consecuencias

- **Positivas:** historial y auditoría completos; sin citas duplicadas por concurrencia.
- **Negativas:** una cita reprogramada varias veces genera una cadena; la UI muestra la última.
- **Obliga a:** un test de concurrencia de doble reprogramación.

## Cuándo revisarla

No se prevé.
