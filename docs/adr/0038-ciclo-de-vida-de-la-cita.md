# ADR-0038: Ciclo de vida de la cita: `Transition` como único escritor del estado, cancelación con códigos y reprogramación con el precio original

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-16 |
| Origen | Plan del hito [M1.06](../milestones/F1-citas-dominio/M1.06-ciclo-de-vida-de-la-cita.md): seis decisiones abiertas que el desarrollador resolvió antes de implementar y ocho delegadas por convención. Concreta [ADR-0019](0019-reprogramar-crea-cita-nueva.md) y se apoya en [ADR-0037](0037-reserva-atomica.md) |

## Contexto

- M1.05 dejó `Appointments::Book` como único creador de citas, pero ningún camino cambiaba el estado. El dominio fija la máquina de estados ([domain/appointments §Estados](../domain/appointments.md#estados)) y ADR-0019 fija que reprogramar crea una cita nueva, bloqueando la original y respondiendo `409` a la segunda petición.
- `appointments` no tenía dónde guardar quién canceló ni por qué, y M3.04 necesita consultar `cancelled_by = customer`.
- El manifest daba al `professional` el mismo `appointments.appointment.read` que a recepción, mientras que la matriz de [04](../architecture/04-access-control.md) dice "ver y editar las propias".
- `Book` toma el precio del catálogo actual. Al reprogramar, eso podía subirle el precio al cliente sin que nadie lo decidiera.
- El alcance pedía "`lock_version` para ediciones de notas", pero no había endpoint para leer ni editar las notas (ADR-0037 las dejó fuera de la respuesta del `POST`).

## Decisión

1. **La máquina de estados es un dato.** `Appointments::Transitions` es la tabla de acciones (`confirm`, `check_in`, `complete`, `no_show`, `cancel`, `reschedule`). Para cada acción guarda su estado destino, sus orígenes, su evento, si `update_own` la cubre, si exige que la cita haya empezado (solo `no_show`) y qué columnas admite además del estado (solo `cancel`).
2. **`Appointments::Transition` es el único escritor de `status`.**
   - Bloquea la fila con `Appointment.lock.find`, que respeta el scope del tenant (`lock!`/`reload` lo ignoran).
   - Comprueba la regla contra el estado bloqueado y mueve la fila con un `UPDATE … WHERE status IN (<orígenes>)`. Cero filas afectadas es `409 appointments.invalid_transition` (`status: not_allowed`). Un `no_show` antes del inicio es el mismo `409` con `status: too_early`.
   - El mismo `UPDATE` sube `lock_version` y `updated_at`, de modo que una edición con la versión vieja recibe `409 resource.stale`.
   - El evento `appointments.appointment_<estado>.v1` y la auditoría (`before: { status }`, `after: { status, … }`) van en el mismo savepoint.
   - Un bloque opcional corre dentro de ese savepoint después del `UPDATE`: si falla, revierte la transición, y lo que devuelve se suma al evento y a la auditoría.
   - El cop `Ceiba/AppointmentStatusWrite` prohíbe escribir `status` fuera de `transition.rb` en el pack de citas.
3. **Cancelar guarda quién y por qué como códigos.** Columnas anulables `cancelled_by` (`staff`, `customer`, `system`) y `cancellation_reason` (`customer_request`, `professional_unavailable`, `business_decision`, `other`), sin texto libre. Las protegen CHECKs con `OR`, añadidos `NOT VALID` y validados en otra migración, más `chk_appointments_cancellation`: una cita está `cancelled` si y solo si tiene ambos. El panel cancela con `cancelled_by: staff`. La ventana de cancelación del cliente es de M3.04.
4. **Reprogramar es una transición con una reserva dentro.** `Reschedule` hace en una sola transacción, en este orden:
   1. Bloquea la original.
   2. La pasa a `rescheduled`; desde ese momento deja de bloquear, así que se puede mover unos minutos sobre sí misma.
   3. Llama a `Book` con `rescheduled_from`.

   La cita nueva conserva el cliente, los servicios en su orden, las notas y **el precio y la moneda de cada línea del snapshot original**: `Book` los deriva del snapshot de `rescheduled_from` y no acepta precios del llamador, así que ningún otro llamador puede reservar a un precio inventado; una original cuyo snapshot no cubre exactamente los servicios reservados es un error del llamador. La duración es la del catálogo actual, porque el motor valida el bloque. Si `Book` rechaza la reserva (hueco ocupado, servicio archivado, cliente inactivo), todo se revierte y la original sigue igual. Si otra petición ganó la carrera, la segunda espera el bloqueo de la fila, encuentra la cita `rescheduled` y recibe `invalid_transition`. El orden de los candados es fila, persona y recurso, y ningún otro camino toma un candado consultivo antes de bloquear la fila de una cita. `Reschedule` recibe `source:`, para que M3.04 reprograme como cliente sin cambiar la firma. Sin `professional_id`, el panel usa el profesional de la cita aunque ya no esté asignado a la sucursal, y el motor responde `422 not_assigned` en vez de un `404` engañoso. La cita nueva nace `scheduled` y con el `source` de quien reprograma, a propósito: mover la cita exige volver a confirmarla, y `source` dice quién creó esa fila (el panel, o el cliente en M3.04), no el canal de la reserva original, que sigue en la cadena `rescheduled_from`. `professional_id: any` responde el mismo `422 appointments.booking_invalid` (`any_not_allowed`) que al reservar. En el outbox, el `appointment_booked.v1` de la cita nueva va antes que el `appointment_rescheduled.v1` de la original.
5. **Permisos:**
   - Todas las acciones y el detalle exigen `appointments.appointment.update` en la sucursal.
   - `appointments.appointment.update_own` cubre `confirm`, `check_in`, `complete` y `no_show`, el detalle y las notas, solo sobre las citas propias: la ficha del profesional de la cita está vinculada al usuario y sigue asignada a la sucursal de la ruta (`Professional.of_user`).
   - Cancelar y reprogramar quedan para `update`.
   - El permiso nuevo `appointments.appointment.read_own` reemplaza a `read` en el rol `professional`, y su agenda solo lista sus citas.
   - El ítem de navegación `agenda` acepta una lista de permisos (basta cualquiera); `/me` no cambia de forma.
   - Leer los clientes de sus citas queda fuera.
6. **Notas:** `GET …/appointments/:appointment_id` devuelve el detalle con `notes`, y `PATCH` del mismo recurso edita solo las notas, con `lock_version` y la clave `notes` obligatorios (sin la clave, `400`: solo un `null` explícito las borra). Ambos piden el mismo permiso que editar la cita. La edición se audita sin el texto y solo si las notas cambian. Las notas de una cita `rescheduled` no se editan (`409 appointments.invalid_transition`, `status: rescheduled`): se copiaron a la cita nueva y se editan allí, sin dos copias que diverjan; las de una cita cancelada o completada siguen editables para anotaciones posteriores. Unas notas de más de 500 caracteres responden la validación genérica de una edición (`422 validation.failed`), no el `appointments.booking_invalid` de la reserva: se acepta la diferencia y el contrato la documenta.
7. **Agenda:** `GET …/branches/:branch_id/appointments?from&to&professional_id`.
   - `from` y `to` son fechas locales de la sucursal, ambas incluidas, con un rango de hasta 31 días.
   - Devuelve todas las citas, en cualquier estado, ordenadas por `starts_at, id`.
   - **Sin cursor**, a diferencia de [07](../architecture/07-api-contract.md): la agenda necesita el rango entero. A cambio, un límite duro de 1000 citas responde `422 appointments.agenda_invalid` (`too_many_appointments`) en vez de truncar.
   - Las líneas se precargan filtradas por empresa, así que el número de consultas es fijo.
8. **Eventos nuevos** (solo ids, estados y horas): `appointment_confirmed`, `appointment_checked_in`, `appointment_completed`, `appointment_no_show`, `appointment_cancelled` (con los códigos de quién y por qué) y `appointment_rescheduled` (con `new_appointment_id`), todos `.v1`.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| Motivo y `cancelled_by` solo en la auditoría y el evento | Sin cambio de esquema | M3.04 y la agenda tendrían que leer la auditoría |
| Motivo como texto libre cifrado | Más expresivo | PII nueva y otra decisión sobre quién la lee |
| Profesional con `read`: ve toda la sucursal y la UI filtra | Cero cambios | Contradice la matriz; el filtro solo existiría en el frontend |
| Filtrar a quien tiene `update_own` sin `update` | Sin permiso nuevo | Deduce la lectura de la falta de un permiso de edición |
| `update_own` solo para `complete` y `no_show` | Mínimo privilegio literal | Sin recepción, el profesional no puede hacer check-in y no llega a `completed` |
| Reprogramar con el precio del catálogo actual | `Book` sin cambios | Mover una cita puede subirle el precio al cliente |
| `record.lock!` para bloquear la fila | Idiomático | `reload` ignora el scope del tenant: encontraba la fila de otra organización donde no hay RLS |
| Listado con cursor | Coherente con 07 | La agenda pediría varias páginas para mostrar una semana |

## Consecuencias

- **Positivas:**
  - Ningún estado imposible: la base solo cambia por la tabla de transiciones.
  - Dos reprogramaciones simultáneas dejan una sola sucesora; está probado por dominio y por HTTP, y una mutación sin `FOR UPDATE` ni `UPDATE` condicionado pone los tests en rojo.
  - Toda transición deja un evento y una auditoría con el estado anterior y el nuevo.
  - El cliente conserva el precio al reprogramar.
  - El profesional ve y toca solo lo suyo.
- **Negativas / costos aceptados:**
  - El filtro global de parámetros oculta `cancellation_reason` en la auditoría (`[FILTERED]`, por la coincidencia parcial de `:reason`), pero el código queda en la fila (final) y en el evento.
  - Si la moneda de la empresa cambió, una reprogramación conserva la moneda original.
  - El listado se desvía de la paginación por cursor.
  - Siguen fuera de alcance, como en M1.05:
    - la elegibilidad se lee antes de los candados (también al reprogramar);
    - ni los candados ni el `FOR UPDATE` tienen `lock_timeout`;
    - la moneda sale de la empresa.
- **Qué obliga a hacer:**
  - **Paso de despliegue:** quitar `appointments.appointment.read` al rol `professional` es una poda del catálogo de permisos. En toda base ya sincronizada, `access:sync` (encadenado a `db:migrate`, `db:prepare` y `db:seed`) se niega a podar sin `ACCESS_SYNC_ALLOW_PRUNE=1`; hasta entonces el profesional conserva `read`. Se despliega una vez con esa variable en cada entorno.
  - El panel refleja la misma regla: la ruta y el menú de la agenda aparecen con `read` o con `read_own`.
  - El cop `Ceiba/AppointmentStatusWrite` en CI.
  - Que `manifest_spec` compare los eventos de `Transitions` con `publishes`, porque la suite de eventos solo descubre nombres literales.
  - Que quien reprograme o cancele desde otra superficie (M3.04) llame a `Reschedule`/`Cancel`.
  - Que todo estado nuevo entre por la tabla de transiciones y por el CHECK de `status`.

## Cuándo revisarla

Si aparece un estado nuevo (por ejemplo, lista de espera), si una agenda real supera el límite de 1000 citas en 31 días, si el negocio pide motivos de cancelación en texto libre o si hay que proteger contra esperas largas con `lock_timeout`.
