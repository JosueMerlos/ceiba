# ADR-0029: Citas con varios servicios y precios congelados

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-06 |
| Origen | `plans/plan-ecosistema-modular-modulo-citas.md` §4 |

## Decisión

Una cita agrupa uno o más servicios en `appointment_services`, que **congela** la duración, el precio y la moneda vigentes al reservar. La duración total es la suma de los servicios más los buffers; el motor de disponibilidad siempre calcula sobre ese total. "Corte + tinte" es una cita, no dos.

## Consecuencias

- **Positivas:** editar el catálogo no altera el historial; facturación futura con datos fiables.
- **Obliga a:** el contrato del motor con una lista de servicios.

## Cuándo revisarla

Si se necesita que servicios de una misma cita los hagan profesionales distintos en secuencia (posible extensión).
