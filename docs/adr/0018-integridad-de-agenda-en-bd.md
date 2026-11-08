# ADR-0018: La integridad de la agenda la garantiza la base de datos, con un único punto de entrada

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §4 y Fase 1 |

## Contexto

Dos reservas simultáneas del mismo hueco son inevitables (staff y página pública a la vez). Las validaciones de la aplicación no lo impiden bajo concurrencia.

## Decisión

- El intervalo **efectivo** de cada cita (servicios + buffers) se guarda ya calculado en `blocks_from`/`blocks_to` (snapshot inmutable).
- **Exclusion constraints** separadas para el profesional y para el recurso, sobre `tstzrange(blocks_from, blocks_to)`, excluyendo los estados `cancelled` y `rescheduled`.
- **Único punto de entrada:** `Appointments::Book` crea todas las citas, traduce la violación de la constraint en `409 slot_unavailable` y además valida la **persona** entre empresas (la constraint cubre registros, no personas).
- "El motor sugiere; la base decide."

## Consecuencias

- **Positivas:** imposible una doble reserva por profesional o recurso, venga de donde venga.
- **Negativas:** la doble reserva de la persona entre empresas solo se valida en la aplicación (con bloqueo de la persona).
- **Obliga a:** `btree_gist`; tests de concurrencia; prohibir `Appointment.create` fuera de `Book`.

## Cuándo revisarla

Si se introduce capacidad mayor a uno por franja (clases grupales): requerirá otro modelo.
