# ADR-0037: Reserva atómica: `Book` como único creador, `tsrange`, candados por persona y por tipo de recurso

| Campo | Valor |
| --- | --- |
| Estado | aceptada |
| Fecha | 2026-11-12 |
| Origen | Plan del hito [M1.05](../milestones/F1-citas-dominio/M1.05-reserva-atomica.md): seis decisiones abiertas que el desarrollador resolvió antes de implementar y diez delegadas por convención. Concreta [ADR-0018](0018-integridad-de-agenda-en-bd.md), [ADR-0020](0020-persona-separada-de-profesional.md) y [ADR-0029](0029-citas-multi-servicio.md) |

## Contexto

- [ADR-0018](0018-integridad-de-agenda-en-bd.md) decidió que la base de datos es el árbitro final de la agenda, pero M1.03 y M1.04 dejaron `appointments` sin constraints de agenda: el motor de disponibilidad solo *sugiere* huecos.
- La SQL de ADR-0018 usa `tstzrange`, pero `blocks_from` y `blocks_to` son `timestamp without time zone` (guardan UTC). Sobre una columna sin zona, `tstzrange` depende del `TimeZone` de la sesión.
- strong_migrations 2.8.0 rechaza `add_exclusion_constraint` y `execute` sobre una tabla existente, y PostgreSQL no tiene `NOT VALID` ni `USING INDEX` para `EXCLUDE`: no hay una variante segura sobre una tabla que ya existe. Dentro del bloque de creación de una tabla, `t.exclusion_constraint` sí pasa (precedente: `weekly_schedules`).
- La "persona" de [ADR-0020](0020-persona-separada-de-profesional.md) es `professionals.user_id`, no el cliente, que es por empresa a propósito ([ADR-0021](0021-cliente-unico-por-empresa.md)). Una constraint de la base solo ve registros de un mismo `professional_id`; el mismo usuario puede tener fichas en otras empresas del grupo.
- La caché pública del motor puede ir hasta 30 s por detrás, y el motor no resta las citas de la persona en otra empresa.
- Las dos constraints de exclusión de profesional y de recurso son independientes, así que dos reservas con profesionales distintos que piden el mismo tipo de recurso pueden competir por sillas distintas y, sin cuidado, esperarse mutuamente.

## Decisión

1. **`appointments` se recrea.** Una migración con una guarda ("la tabla está vacía o falla") hace `drop_table` y `create_tenant_table` con todas las columnas, constraints e índices, sin `safety_assured`. El `down` es simétrico y también falla si hay filas. Es posible porque la tabla tiene 0 filas, nada la referencia con una FK y no hay ningún entorno con datos reales; una vez haya datos en producción, este patrón ya no sirve.
2. **`tsrange(blocks_from, blocks_to, '[)')`** en las dos exclusiones (`no_overlap_professional` y `no_overlap_resource`), con `WHERE status NOT IN ('cancelled', 'rescheduled')`; `no_overlap_resource` además exige `resource_id IS NOT NULL`. Intervalos semiabiertos: una cita que termina a las 11:00 no choca con una que empieza a las 11:00.
3. **Claves foráneas compuestas que atan lo que importa:** el recurso a la **sucursal** de la cita, `(organization_id, branch_id, resource_id)` contra `resources`, con el índice único nuevo `uq_resources_org_branch_id`; el cliente a la **empresa**, `(organization_id, company_id, customer_id)` contra `customers`, con `uq_customers_org_company_id`. Ambos índices son aditivos y se crean de forma concurrente.
4. **La persona se protege en la aplicación.** `Book` toma `pg_advisory_xact_lock` sobre la persona (`professionals.user_id`, o `professional.id` si es NULL) y, después de tenerlo, consulta las citas que bloquean de **otras** fichas con el mismo `user_id` en cualquier empresa de la organización. Si solapan, `409 appointments.person_unavailable`. Un profesional sin usuario no está protegido entre empresas porque no hay forma de saber que es la misma persona.
5. **Segundo candado por (sucursal, tipo de recurso)**, siempre **después** del de la persona (orden fijo, para que dos reservas nunca se esperen mutuamente). Sin él, dos profesionales distintos que piden "una silla" podrían elegir la misma silla libre a la vez y el perdedor vería una violación de la constraint de recurso en lugar de pasar a la siguiente silla. Un `ActiveRecord::Deadlocked` residual se traduce también a `409`; igual que la FK compuesta del recurso (`fk_appointments_resource`) si el recurso desaparece o cambia de sucursal tras la revalidación. Cualquier otra FK rota sale como error. Cada traducción silenciosa se reporta con `Rails.error.report(handled: true)` y solo ids.
6. **Revalidación contra el motor, después de los candados.** `Book` vuelve a pedir la disponibilidad y exige que el inicio exacto siga ofrecido, con el profesional y el recurso que el motor asigna. Un hueco que ya no está, ya sea por una caché atrasada o por la carrera de otra petición, es `409 appointments.slot_unavailable`. Quien espera el candado lee la fila ya confirmada del ganador, así que el perdedor casi nunca llega a la constraint. La constraint es la última barrera: su `ExclusionViolation` también es `SlotUnavailable`.
7. **Entrada de la reserva:** un `starts_at` anterior a `now` es siempre `422 booking_invalid` (`starts_at` `in_the_past`), antes de que el motor lo vea, y uno con segundos o fracciones es `not_on_minute`; el instante ISO 8601 exige segundos y una fecha que no existe (30 de febrero) es `400`. **`any` se rechaza al reservar:** `422 appointments.booking_invalid` con `professional_id` `any_not_allowed`. El candado por persona necesita un profesional conocido de antemano; el cliente envía el `professional_id` del hueco que mostró la disponibilidad. La reserva pública con "cualquiera" se resuelve en M3.02.
8. **Ventana del panel:** el motor gana el parámetro `booking_window: :customer | :staff`. Con `source = "panel"`, `Book` usa `:staff` y no aplica la anticipación mínima ni la máxima; siguen valiendo los horarios, las ausencias, la rejilla y que el bloque no empiece antes de `now`. La reserva pública usa `:customer`. **La disponibilidad del panel (`GET …/branches/:branch_id/availability`) usa la misma ventana `:staff`**, para que la rejilla no oculte huecos que el `POST` del panel aceptaría; la disponibilidad pública sigue con `:customer` y su clave de caché no cambia.
9. **Quién creó la cita:** `created_by_type` (`user`, `api_key`, `system`, `public_token`, `platform_staff`; con CHECK) y `created_by_id` (uuid anulable, sin FK), con el mismo contrato que `audit_events` y `Access::Principal`.
10. **`notes` cifradas** (`encrypts :notes`, no determinista, como `customers.notes`), con un máximo de 500 caracteres validado en `Book`. En la auditoría salen filtradas y nunca van en el evento.
11. **`Book` es el único creador de citas.** Dentro de un savepoint (`requires_new: true`) inserta la cita y las líneas de `appointment_services` (el snapshot inmutable de duración y precio), publica `appointments.appointment_booked.v1` en el outbox y registra la auditoría, todo en la misma transacción. El savepoint importa para los llamadores que rescatan un conflicto y siguen (Reschedule, jobs). El cop `Ceiba/AppointmentCreation` prohíbe `create`, `create!`, `new`, `build`, `insert`, `insert_all`, `upsert`, `upsert_all`, `create_with`, `find_or_create_by`, `find_or_initialize_by`, `first_or_create`, `first_or_initialize` y `create_or_find_by` (con `!`) sobre `Appointment` y `AppointmentService`, también al final de una cadena (`Appointment.where(...).create!`), fuera de `book.rb` (`AllowedFiles`, comparado por el final de la ruta, así que no depende del directorio desde el que se ejecute RuboCop) y de los specs (la factory es infraestructura de test).
12. **Endpoint del panel:** `POST …/appointments/branches/:branch_id/appointments`, con `Idempotency-Key` obligatoria y el permiso `appointments.appointment.create` a alcance de sucursal (la matriz no cambia). La autorización va **antes** del filtro de idempotencia y un `409` de agenda no consume la clave, porque el error sale de la transacción de la petición y esta hace rollback.
13. **Pool de conexiones de test de 12** (antes 5), porque los specs de concurrencia lanzan 10 hilos con una conexión cada uno, más la del ejemplo y algo de margen.

## Alternativas consideradas

| Opción | A favor | En contra |
| --- | --- | --- |
| `safety_assured` en las dos `add_exclusion_constraint` | Una migración más pequeña | Deja un precedente de bypass; el desarrollador lo prohibió |
| Desactivar el check de strong_migrations globalmente | Una línea | Apaga la protección para siempre y en todas las tablas |
| `tstzrange` sobre columnas sin zona | Coincide con ADR-0018 | El resultado depende del `TimeZone` de la sesión |
| Proteger también al cliente entre empresas | Evita que un paciente se agende en dos clínicas a la vez | No hay vínculo entre clientes de distintas empresas (ADR-0021); sería emparejar por teléfono cifrado y cambia PII |
| Aceptar `any` en `Book` | Menos `409` en la reserva pública | Dos pasadas del motor, un candado que no se conoce de antemano y más superficie |
| Las mismas reglas de ventana para todos los orígenes | No cambia el motor | Una recepcionista no podría agendar para dentro de una hora ni un control a 3 meses |
| `created_by_user_id` con FK a `users` | Una FK real | No representa una API key ni la reserva pública |
| Notas en texto plano con `CHECK (length <= 500)` | Constraint en la BD y búsqueda posible | Texto libre con posible PII en claro, en la BD y en los backups |
| Sin segundo candado (solo el de persona) | Un candado menos | Carrera por la misma silla entre profesionales distintos |

## Consecuencias

- **Positivas:** una doble reserva del mismo profesional o recurso es imposible venga de donde venga; diez peticiones simultáneas al mismo hueco dan exactamente un `201` y nueve `409` (probado por dominio y por HTTP); el precio queda congelado en `appointment_services`; el evento y la auditoría nacen con la cita.
- **Negativas / costos aceptados:** la protección de la persona entre empresas es una regla de aplicación (no de la base) y no cubre a un profesional sin usuario; el motor puede ofrecer un hueco que `Book` rechace con `person_unavailable` (seguimiento para M3.02); las reservas de un mismo tipo de recurso en una sucursal se serializan; el patrón de recrear una tabla vacía no se repite cuando haya datos reales.
- **Qué obliga a hacer:** tests de concurrencia (dominio y HTTP) estables en 20 ejecuciones; el cop `Ceiba/AppointmentCreation` en CI; quien reprograme (M1.06) o reserve desde la superficie pública (M3.02) llama a `Book`, nunca inserta; todo cambio de las exclusiones se hace en una tabla nueva o con el mismo cuidado que esta migración.

## Cuándo revisarla

Si aparece capacidad mayor a uno por franja (clases grupales), si hay que proteger al cliente entre empresas, si las reservas de un tipo de recurso en una sucursal saturan el candado, o cuando existan datos reales en `appointments` y haga falta cambiar una constraint.
