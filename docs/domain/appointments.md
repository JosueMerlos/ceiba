# Dominio: módulo de citas (`appointments`)

> Migrado desde `plans/plan-ecosistema-modular-modulo-citas.md` §4–§5 y Fase 1. Decisiones: [ADR-0018](../adr/0018-integridad-de-agenda-en-bd.md), [ADR-0019](../adr/0019-reprogramar-crea-cita-nueva.md), [ADR-0020](../adr/0020-persona-separada-de-profesional.md), [ADR-0029](../adr/0029-citas-multi-servicio.md), [ADR-0034](../adr/0034-horarios-ausencias-y-permisos-de-profesionales-y-recursos.md). Hitos: F1–F3.

## Alcance del MVP

**Incluye:** catálogo de servicios; profesionales y recursos con horarios, descansos y ausencias; agenda del staff; página pública `/c/:slug`; recordatorios por correo y WhatsApp; cancelación y reprogramación por el cliente.

**Excluye:** pagos y depósitos, facturación, inventario, historial clínico, sincronización con calendarios externos, citas recurrentes, capacidad mayor a uno por franja (clases), lista de espera (P2), duración variable (P2).

## Modelo

```
services                      (empresa)
  id, organization_id, company_id, name, duration_minutes, buffer_before_minutes, buffer_after_minutes,
  price_minor, currency, active, position, category NULL (varchar(60), recortada; CHECK sin blancos), archived_at,
  created_at, updated_at
branch_service_overrides      (sucursal: solo duración y/o precio)
  id, organization_id, company_id, branch_id, service_id, duration_minutes NULL, price_minor NULL,
  created_at, updated_at                              -- UNIQUE(branch_id, service_id); al menos un valor no nulo

professionals                 (empresa)
  id, organization_id, company_id, user_id NULL, display_name, phone_e164 NULL, email NULL, active, archived_at,
  created_at, updated_at                              -- phone_e164 y email: PII cifrada (encrypts, determinista)
                                                      -- UNIQUE parcial (company_id, user_id) WHERE user_id IS NOT NULL
professional_branch_assignments
  id, organization_id, company_id, professional_id, branch_id, created_at, updated_at
                                                      -- FKs triples a professionals y branches; UNIQUE(professional_id, branch_id)
professional_services         (qué servicios presta)
  id, organization_id, company_id, professional_id, service_id, created_at, updated_at

resources                     (sucursal)
  id, organization_id, company_id, branch_id, name, kind ('chair'|'room'|'equipment'), active, archived_at,
  created_at, updated_at
service_resource_requirements (qué TIPO de recurso necesita un servicio)
  id, organization_id, company_id, service_id, kind, created_at, updated_at   -- UNIQUE(service_id, kind)

weekly_schedules              (horario semanal local)
  id, organization_id, company_id, branch_id, owner_type ('branch'|'professional'|'resource'),
  professional_id NULL, resource_id NULL, weekday (0-6, 0 = domingo), starts_at_local (time), ends_at_local (time),
  created_at, updated_at
time_offs
  id, organization_id, company_id, owner_type ('professional'|'resource'), professional_id NULL, resource_id NULL,
  starts_at (timestamptz), ends_at, reason NULL (texto libre, hasta 200, sin datos de salud), created_at, updated_at

appointments
  id, organization_id, company_id, branch_id, customer_id, professional_id, resource_id NULL,
  starts_at, ends_at, blocks_from, blocks_to,          -- blocks_* incluye buffers (snapshot)
  status, source, rescheduled_from_id NULL, notes, lock_version, created_by (actor),
  cancelled_by NULL, cancellation_reason NULL, timestamps
appointment_services
  appointment_id, service_id, position, duration_minutes, buffer_before, buffer_after, price_minor, currency
```

Todas son tablas tenant (`create_tenant_table`) con FKs compuestas hacia sus padres.

### Cómo quedó implementado (M1.02)

- **Dueño explícito, no polimórfico.** `weekly_schedules` y `time_offs` llevan `professional_id` y `resource_id` anulables más `owner_type`, con un CHECK de coherencia (solo la columna del tipo de dueño está llena) y una clave foránea compuesta por columna: un horario de profesional exige una asignación a esa sucursal `(organization_id, company_id, professional_id, branch_id)` y uno de recurso exige que el recurso sea de esa sucursal. Un `owner_id` polimórfico no admite FK ([ADR-0034](../adr/0034-horarios-ausencias-y-permisos-de-profesionales-y-recursos.md)).
- **Requisitos por `kind`.** `service_resource_requirements` pide un tipo de recurso (`chair`, `room`, `equipment`) y no un recurso concreto: el motor exige un recurso compatible libre en la sucursal ([M1.04](../milestones/F1-citas-dominio/M1.04-disponibilidad-completa.md)).
- **Franjas de minuto entero y sin cruzar la medianoche.** CHECKs: `weekday` entre 0 y 6, `starts_at_local < ends_at_local` y precisión de minuto (sin ella, una franja de menos de un minuto da un rango vacío y escapa a la exclusión).
- **Sin solapes, garantizado por la BD.** Tres exclusion constraints parciales sobre `int4range` de minutos del día, semiabierto `[)` (9–13 y 13–15 no solapan): por sucursal (`owner_type = 'branch'`), por profesional (en **todas** sus sucursales: una persona no está en dos sitios a la vez) y por recurso. El modelo da el mismo error como `slots: overlap` (`422`) antes de llegar a la BD.
- **El `PUT` del horario reemplaza todas las franjas del dueño en esa sucursal** en una transacción, serializada por dueño con un candado consultivo.
- **Ausencias solapadas del mismo dueño se permiten**: el motor resta la unión.
- **Sucursal sin horario = cerrada.** `on_enable` del módulo (`Appointments::Lifecycle::OnEnable`) da lunes a sábado de 08:00 a 18:00 a las sucursales que existen **al activar** y que no tienen horario; una sucursal creada después empieza sin horario (cerrada para el motor) hasta que el gerente lo configura (M2.01).

### Cómo quedó implementado (M1.03)

- **Núcleo puro y cargador de consultas fijas.** `Appointments::Availability::{Interval, IntervalSet, WeeklyExpander, SlotFinder, Calculator}` no usan ActiveRecord (intervalos UTC semiabiertos); `DataLoader` es lo único que consulta y emite un número fijo de consultas, sea cual sea el rango. `Availability.call` devuelve un `Result` con `slots`, `duration_minutes` y `step_minutes` ([ADR-0035](../adr/0035-motor-de-disponibilidad-caso-base.md)).
- **Agenda única por persona.** Las citas y ausencias del profesional restan en **todas** sus sucursales; las franjas semanales, solo las de la sucursal pedida. Quien consulta ve libre/ocupado, nunca el detalle de otra sucursal.
- **Hora local a UTC en un solo lugar** (`WeeklyExpander`): una hora inexistente se recorta a la transición, una ambigua toma su primera ocurrencia y la contención es cronológica. No se usa `TimeZone#local`.
- **Rejilla del reloj local:** un inicio es válido si su minuto del día local es múltiplo de `slot_step_minutes`. `min_lead_time_minutes` y `max_advance_days` (`now + N × 24 h`) se miden desde `now`.
- **`appointments` mínima:** `status` (por defecto `scheduled`) y las columnas que lee el motor (`company_id`, `branch_id`, `professional_id`, `starts_at`, `ends_at`, `blocks_from`, `blocks_to`), con claves foráneas compuestas y sin constraints de agenda. M1.05 añade `customer_id`, `resource_id`, `source`, `notes`, `lock_version`, `created_by` y `rescheduled_from_id` junto con las constraints. `Appointment.blocking` excluye `cancelled` y `rescheduled`; `Appointment.overlapping` usa `blocks_*` y es semiabierto.
- **Endpoint** `GET …/appointments/branches/:branch_id/availability?service_id&professional_id&from&to` con el permiso `appointments.appointment.create` a alcance de sucursal; rango de hasta 31 días; errores `400` (`request.invalid`, `request.bad_request`, también para un parámetro repetido), `403`, `404` y `422 appointments.availability_invalid`.
- **Una sucursal inactiva está cerrada:** `ensure_eligible!` responde `422` con `branch_id` `inactive`. También se rechaza un `from` anterior a ayer en la hora local de la sucursal (`from` `too_early`) y, para los llamadores que no pasan por el controlador, un registro de otra empresa (`wrong_company`).
- **Aislamiento por empresa:** las consultas del cargador filtran por `company_id` además de por organización. Los límites inferiores se redondean hacia arriba al segundo, así que un hueco no invade por una fracción una ausencia que termina en `hh:mm:ss.5`.

### Cómo quedó implementado (M1.04)

- **Varios servicios:** duración = Σ duraciones con override; bloque = buffer previo del primero + duración + buffer posterior del último, y el bloque entero cabe en el horario; precio = Σ precios con override, en la moneda de la empresa ([ADR-0036](../adr/0036-motor-de-disponibilidad-completo-y-superficie-publica.md)).
- **`:any`:** elegibles = asignados a la sucursal, activos y que prestan todos los servicios; para cada inicio gana el de menos citas que bloquean ese día local (en todas sus sucursales), con desempate por `id`.
- **Recursos:** un solo tipo por petición (`multiple_resource_kinds` si se piden más); el recurso libre de menor `id`; un recurso sin franjas sigue el horario de la sucursal. `appointments.resource_id` existe desde este hito (sin `no_overlap_resource`, que llega con `Book`).
- **Superficie pública** `GET /api/public/v1/c/:slug/availability`: sin datos personales, `404` uniforme, hasta 14 días, caché de 30 s y regla 5 de Rack::Attack.

### Cómo quedó implementado (M1.05)

- **`appointments` recreada con las constraints de agenda** (la tabla estaba vacía; una guarda hace fallar la migración si no lo está): `no_overlap_professional` y `no_overlap_resource` sobre `tsrange [)`, `chk_appointments_valid_interval`, FKs compuestas del recurso (a la sucursal) y del cliente (a la empresa), y las columnas `customer_id`, `source`, `notes` (cifradas), `lock_version`, `created_by_type`/`created_by_id` y `rescheduled_from_id`. `appointment_services` guarda el snapshot inmutable de duración, buffers y precio por servicio (un trigger rechaza todo `UPDATE`; el `DELETE` en cascada sigue permitido), y `chk_appointments_created_by_user_id` exige el id cuando el actor es un usuario; la respuesta del `POST` no incluye `notes` ([ADR-0037](../adr/0037-reserva-atomica.md)).
- **`Book` es el único creador**, y el cop `Ceiba/AppointmentCreation` lo hace cumplir (citas y líneas de `appointment_services`, también en cadenas como `Appointment.where(...).create!`): valida la elegibilidad una sola vez, toma `pg_advisory_xact_lock` sobre la persona (`professionals.user_id`, o el id del profesional) y después sobre (sucursal, tipo de recurso), siempre en ese orden; revalida contra el motor; comprueba la persona entre empresas; inserta; publica el evento y audita, todo en un savepoint.
- **Conflictos:** un hueco que ya no se ofrece o una `ExclusionViolation` o `Deadlocked` es `409 appointments.slot_unavailable`; la misma persona ocupada en otra empresa es `409 appointments.person_unavailable`. El perdedor de una carrera casi siempre ve al ganador en la revalidación, no en la constraint.
- **Solo un profesional concreto:** `any` es `422 appointments.booking_invalid` (`professional_id` `any_not_allowed`). El panel reserva con `booking_window: :staff` (sin anticipación mínima ni máxima). La disponibilidad del panel usa la misma ventana (`:staff`); la pública, `:customer`.
- **Entrada y auditoría:** un `starts_at` en el pasado es `422 booking_invalid` (`in_the_past`); con segundos o fracción, `not_on_minute`. La auditoría de la reserva guarda también `rescheduled_from_id`, el total, la moneda y las líneas del snapshot. Los `409` que salen de una constraint (exclusión, deadlock o la FK del recurso) se reportan con `Rails.error`.
- **Endpoint** `POST …/appointments/branches/:branch_id/appointments` con `Idempotency-Key` obligatoria y el permiso `appointments.appointment.create` a alcance de sucursal. Responde `201` con la cita, sus líneas y el total, sin datos personales del cliente; un `409` de agenda no consume la clave.
- **Evento** `appointments.appointment_booked.v1`: solo ids y horas, sin `notes` ni datos del cliente.

### Cómo quedó implementado (M1.06)

- **La máquina de estados es un dato** ([ADR-0038](../adr/0038-ciclo-de-vida-de-la-cita.md)). `Appointments::Transitions` dice, para cada acción (`confirm`, `check_in`, `complete`, `no_show`, `cancel`, `reschedule`), su destino, sus orígenes, su evento, si la cubre `update_own` y si exige que la cita haya empezado.
- **`Appointments::Transition` es el único escritor de `status`.**
  - Bloquea la fila con `Appointment.lock.find` (escopado al tenant), revisa la regla contra el estado bloqueado y hace un `UPDATE … WHERE status IN (<orígenes>)`. Cero filas es `409 appointments.invalid_transition`: `not_allowed`, o `too_early` en un `no_show` antes del inicio.
  - El `UPDATE` sube `lock_version` y `updated_at`.
  - El evento y la auditoría (estado anterior y nuevo) van en el mismo savepoint.
  - El cop `Ceiba/AppointmentStatusWrite` prohíbe escribir `status` fuera de `transition.rb`.
- **Cancelar** guarda `cancelled_by` (`staff`, `customer`, `system`) y `cancellation_reason`, un código de lista cerrada (`customer_request`, `professional_unavailable`, `business_decision`, `other`), sin texto libre.
  - Un CHECK exige ambos si y solo si la cita está `cancelled`.
  - El panel cancela como `staff`.
  - El filtro global de parámetros oculta el motivo en la auditoría (`*reason`), pero queda en la fila y en el evento.
- **Reprogramar**, todo en una transacción:
  1. Bloquea la original.
  2. La pasa a `rescheduled`.
  3. Llama a `Book` con `rescheduled_from`. La cita nueva conserva el cliente, los servicios en orden, las notas y el precio de cada línea (que `Book` deriva del snapshot de la original); la duración es la actual. Nace `scheduled` y con el `source` de quien reprograma.

  Un `409` de `Book` lo revierte todo. Una segunda reprogramación simultánea recibe `invalid_transition`. El orden de los candados es fila, persona y recurso.
- **Permisos:**
  - `update` cubre todas las acciones, el detalle y las notas.
  - `update_own` cubre `confirm`, `check_in`, `complete`, `no_show`, el detalle y las notas de las citas propias: la ficha vinculada al usuario y asignada a la sucursal.
  - El `professional` tiene `read_own` en lugar de `read`, y su agenda solo lista sus citas. La navegación acepta varios permisos por entrada.
- **Endpoints** (sucursal de la ruta; una cita de otra sucursal o empresa es `404`):
  - `GET …/appointments?from&to&professional_id`: la agenda, de 1 a 31 días locales, en cualquier estado, sin cursor y con un límite duro de 1000 → `422 appointments.agenda_invalid`;
  - `GET` y `PATCH …/appointments/:appointment_id`: detalle con `notes`, y edición de notas con `lock_version` obligatorio → `409 resource.stale`; las de una cita `rescheduled` no se editan (`409 appointments.invalid_transition`);
  - `POST …/appointments/:appointment_id/{confirm,check_in,complete,no_show,cancel,reschedule}`: `reschedule` exige `Idempotency-Key` y responde `201` con la cita nueva; las demás la aceptan.
- **Eventos** `appointments.appointment_{confirmed,checked_in,completed,no_show,cancelled,rescheduled}.v1`: solo ids, estados y horas; `cancelled` lleva los códigos y `rescheduled` lleva `new_appointment_id`.

### Cómo quedó implementado (M2.07)

- **Contacto del profesional:** `professionals.phone_e164` y `professionals.email`, opcionales y cifrados con Active Record
  Encryption (deterministas, como el cliente; el correo en minúsculas).
  - El teléfono se normaliza a E.164 con `Customers::Phone` y el país de la organización («8888 1234» en Nicaragua queda
    `+50588881234`); un número inválido es `422` sobre `phone`. Vacío se guarda `NULL`.
  - Es PII ([ADR-0043](../adr/0043-rediseno-v2-del-panel.md), enmienda a [ADR-0033](../adr/0033-autorizacion-y-pii-de-clientes-y-servicios.md)):
    solo lo lee quien tiene `appointments.professional.manage` (`ProfessionalPolicy#contact?`); para los demás es `null`.
    El listado y `show_in_branch` no lo incluyen. Ni el profesional ve su propio contacto.
  - La auditoría guarda los nombres de los campos cambiados, nunca los valores; `filter_parameters` cubre `:phone` y `:email`.
- **Categoría del servicio:** `services.category`, texto libre opcional de hasta 60 caracteres que agrupa el catálogo.
  Se recorta («  Uñas  » → «Uñas»), vacía es `NULL` y un CHECK impide blancos. Las sugerencias del panel salen de los
  servicios ya cargados; no hay tabla ni endpoint de categorías.
- **Deuda:** la importación CSV ([ADR-0042](../adr/0042-importacion-csv.md)) no lleva teléfono, correo ni categoría: sus
  plantillas no cambiaron.

## Restricciones críticas

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;

ALTER TABLE appointments ADD CONSTRAINT no_overlap_professional
  EXCLUDE USING gist (professional_id WITH =, tsrange(blocks_from, blocks_to, '[)') WITH &&)
  WHERE (status NOT IN ('cancelled', 'rescheduled'));

ALTER TABLE appointments ADD CONSTRAINT no_overlap_resource
  EXCLUDE USING gist (resource_id WITH =, tsrange(blocks_from, blocks_to, '[)') WITH &&)
  WHERE (resource_id IS NOT NULL AND status NOT IN ('cancelled', 'rescheduled'));

ALTER TABLE appointments ADD CONSTRAINT chk_appointments_valid_interval
  CHECK (starts_at < ends_at AND blocks_from <= starts_at AND blocks_to >= ends_at);
```

> Las columnas `blocks_*` son `timestamp` sin zona (UTC), por eso `tsrange` y no `tstzrange`. El recurso se ata a la sucursal de la cita con una FK compuesta `(organization_id, branch_id, resource_id)` y el cliente a la empresa con `(organization_id, company_id, customer_id)`.

> `no_show` y `completed` siguen bloqueando su intervalo: el tiempo ya ocurrió. Solo `cancelled` y `rescheduled` lo liberan.

## Estados

```mermaid
stateDiagram-v2
  [*] --> scheduled
  scheduled --> confirmed
  scheduled --> checked_in
  scheduled --> cancelled
  scheduled --> rescheduled
  confirmed --> checked_in
  confirmed --> cancelled
  confirmed --> rescheduled
  confirmed --> no_show
  scheduled --> no_show
  checked_in --> completed
  completed --> [*]
  cancelled --> [*]
  rescheduled --> [*]
  no_show --> [*]
```

- Transiciones en `Appointments::Transitions` (tabla de transiciones válidas y su permiso requerido) y aplicadas solo por `Appointments::Transition`. Ningún controlador actualiza `status` directamente (cop `Ceiba/AppointmentStatusWrite`).
- Cada transición: bloqueo de la fila, `UPDATE … WHERE status IN (<origen válido>)` verificando las filas afectadas, auditoría y evento en el outbox, todo en **una** transacción.
- `no_show` solo se permite después de `starts_at`; `completed`, después de `checked_in`.

## Casos de uso (API pública del pack)

| Servicio | Responsabilidad |
| --- | --- |
| `Appointments::Availability.call(company:, branch:, services:, professional:, from_date:, to_date:, now:)` (`professional` es un profesional o `:any`) | Devuelve un `Result(slots:, duration_minutes:, buffer_before_minutes:, buffer_after_minutes:, price_minor:, currency:, step_minutes:)`; cada hueco es `Slot(starts_at, ends_at, professional_id, resource_id)` en UTC, con `ends_at = starts_at + duración` (sin buffers) |
| `Appointments::Book.call(company:, branch:, customer_id:, services:, professional:, starts_at:, source:, notes: nil, actor:, now:, rescheduled_from: nil)` | **Único** creador de citas; con `rescheduled_from`, el precio y la moneda de cada línea salen del snapshot de la original (nunca del llamador); `professional:` es un `Availability::ProfessionalChoice` concreto (`any` es `InvalidBooking`). Dentro de un savepoint toma los candados (persona y tipo de recurso), revalida contra el motor, comprueba la persona entre empresas, inserta la cita y su snapshot de `appointment_services`, publica `appointment_booked.v1` y audita. Errores: `SlotUnavailable` y `PersonUnavailable` (409), `InvalidBooking` y `Availability::InvalidRequest` (422) |
| `Appointments::Transition.call(appointment:, action:, actor:, now:, attributes: {}, &follow_up)` | **Único** escritor del estado: bloquea la fila, aplica la regla de `Transitions` con un `UPDATE` condicionado, sube `lock_version`, publica y audita. Error: `InvalidTransition` (409) |
| `Appointments::Cancel.call(appointment:, reason:, cancelled_by:, actor:, now:)` | Cancela con el código de motivo y quién; `InvalidCancellation` (422) si el motivo falta o no es de la lista |
| `Appointments::Reschedule.call(appointment:, company:, branch:, starts_at:, professional:, source:, actor:, now:)` | Bloquea, marca `rescheduled` y llama a `Book` con `rescheduled_from` y el precio original, todo en una transacción; devuelve la cita nueva |

## Motor de disponibilidad

**Entrada:** empresa, sucursal, lista de servicios, profesional o `:any`, rango de fechas (en la zona de la sucursal).
**Salida:** huecos con duración y precio totalizados.

Algoritmo (por profesional elegible):

1. Servicios → duración = Σ duraciones (con override de sucursal); bloque = buffer previo del primero + duración + buffer posterior del último (los buffers son preparación y limpieza de la cita, no de cada servicio). El precio total = Σ precios (con override), en la moneda de la empresa.
2. Profesionales elegibles: asignados a la sucursal, activos y que prestan **todos** los servicios.
3. Ventanas abiertas = horario de la sucursal ∩ horario del profesional, convertido de hora local a UTC **día por día** (correcto ante DST).
4. Restar ausencias del profesional y citas que bloquean (`blocks_from/blocks_to`).
5. Si los servicios requieren un recurso: intersectar con la disponibilidad de algún recurso compatible.
6. Generar inicios cada `slot_step_minutes` (setting, por defecto 15) donde quepa la duración total.
7. Filtrar por anticipación mínima (`min_lead_time_minutes`, 120) y máxima (`max_advance_days`, 60).
8. `:any` → para cada inicio, el primer profesional libre según una política de reparto (por defecto: el de menor carga del día).

Implementación como objetos puros (sin ActiveRecord en el núcleo: recibe intervalos y devuelve intervalos), con un adaptador que carga los datos en pocas consultas. **El motor sugiere; la base decide.**

## Reglas de negocio

- Todo en UTC; la zona de la sucursal manda en la presentación y en la interpretación de horarios.
- La persona (usuario) no puede tener dos citas solapadas en ninguna empresa del grupo (validado en `Book` con `pg_advisory_xact_lock` sobre el `user_id`).
- La cancelación por el cliente respeta `cancellation_window_hours` (setting); fuera de la ventana, solo el staff puede cancelar.
- Las notas de la cita son operativas; **nunca datos clínicos**.

## Settings del módulo (JSON Schema)

| Clave | Default | Niveles |
| --- | --- | --- |
| `min_lead_time_minutes` | 120 | empresa, sucursal |
| `max_advance_days` | 60 | empresa, sucursal |
| `slot_step_minutes` | 15 | empresa, sucursal |
| `cancellation_window_hours` | 4 | empresa |
| `public_booking_enabled` | true | empresa, sucursal |
| `any_professional_policy` | `least_busy` | empresa |
| `reminders` | `[{ "kind": "24h", "offset_minutes": 1440 }, { "kind": "2h", "offset_minutes": 120 }]` | empresa |
