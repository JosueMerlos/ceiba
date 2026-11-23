# ADR-0041: El listado de la agenda incluye el nombre del cliente

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-18 |
| Origen | Plan del hito [M2.02](../milestones/F2-agenda-interna/M2.02-agenda-del-staff.md): dos decisiones abiertas que el desarrollador resolvió el 2026-11-18. Amplía la excepción de PII de [ADR-0033](0033-autorizacion-y-pii-de-clientes-y-servicios.md) y resuelve lo que [ADR-0038](0038-ciclo-de-vida-de-la-cita.md) dejó fuera sobre "los clientes de sus citas" |

## Contexto

- La agenda muestra quién viene a cada cita, pero `GET …/branches/:branch_id/appointments` solo devolvía `customer_id`.
- `GET …/customers` no filtra por ids y devuelve siempre teléfono, correo y notas. Resolver 40 citas exigía hasta 40 peticiones en cada carga y en cada refresco de 30 s, con más datos personales de los necesarios.
- El `professional` no tiene `platform.customer.read`. La matriz decía que no accede a clientes "hasta que existan las citas (luego, los de sus citas)", y ADR-0033 pedía revisarlo cuando las citas existieran.
- `appointments.appointment.read` lista toda la sucursal y no implica `platform.customer.read`.

## Decisión

1. **El listado de la agenda añade `customer_name`**, el nombre completo del cliente. Es el único dato del cliente que se agrega: nunca teléfono, correo ni notas. El campo existe solo en ese listado (`AgendaAppointment`): detalle, reserva, transiciones y reprogramación siguen sin él.
2. **Quién lo recibe** (`AppointmentPolicy#customer_names?`): quien tiene `platform.customer.read` en la sucursal, o quien tiene `appointments.appointment.read_own` **sin** `appointments.appointment.read`. Este segundo caso es el `professional`, cuyo listado ya contiene solo sus propias citas. Para cualquier otro principal el campo es `null`.
3. **El pack de citas pide los nombres por la API pública de clientes** (`Customers::Lookup.full_names`), con una sola consulta filtrada por empresa. Incluye clientes archivados, porque sus citas siguen existiendo.
4. `customer_name` se añade a `filter_parameters`. No se escribe en logs, auditoría, eventos ni mensajes de error.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| **`customer_name` solo en el listado de agenda** | Una sola petición; solo sale el nombre | Amplía la excepción de PII a otro endpoint. **Elegida** |
| Filtro `ids` en `GET customers` | La PII sigue en el recurso cliente | Lleva teléfono, correo y notas de todos al navegador; no resuelve al `professional` |
| Un `GET customers/:id` por cita | Sin cambios de API | Hasta 40 peticiones por carga y por refresco; misma sobreexposición |
| El `professional` sin nombre del cliente | Ninguna PII nueva | No sabe a quién atiende; contradice "los de sus citas" |

## Consecuencias

- **Positivas:** la agenda carga con un número fijo de consultas; el `professional` ve a quién atiende sin obtener acceso al recurso cliente.
- **Negativas / costos aceptados:** un segundo endpoint devuelve un dato personal, y hay que mantener la excepción acotada.
- **Qué obliga a hacer:** todo listado nuevo que quiera el nombre pasa por una decisión propia; los specs fijan `null` para `read` sin `customer.read`, también si además tiene `read_own`. Cuando las API keys autoricen de verdad, deben pasar por la misma compuerta.

## Cuándo revisarla

Si otra pantalla necesita datos del cliente fuera de su recurso, si el `professional` necesita contacto del cliente, o cuando las API keys dejen de denegar todo.
