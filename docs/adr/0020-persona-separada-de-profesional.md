# ADR-0020: La persona (usuario) está separada del registro profesional

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-07 |
| Origen | `plans/plan-ecosistema-modular-pendientes.md` §2.4 y §5 (decisión 5) |

## Contexto

Caso real: una especialista atiende dos días en dos sucursales de una empresa y el resto de la semana en otra empresa del mismo grupo.

## Decisión

El `professional` es un registro **por empresa** (horario, servicios, citas) y se asigna a sucursales. Referencia opcionalmente a un `user` (la persona). Una persona puede tener registros profesionales en varias empresas del grupo. `Appointments::Book` valida que la **persona** no tenga otra cita en ninguna empresa del grupo en el mismo rango.

## Consecuencias

- **Positivas:** horarios y catálogos independientes por empresa, con la persona protegida de dobles reservas.
- **Negativas:** la validación cruzada es de aplicación (bloqueo por `user_id` dentro de la transacción).
- **Obliga a:** un test de doble reserva de persona entre empresas.

## Cuándo revisarla

No se prevé.
