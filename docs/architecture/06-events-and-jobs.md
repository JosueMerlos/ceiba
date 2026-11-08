# 06 — Eventos de dominio y jobs

> Decisiones: [ADR-0009](../adr/0009-sidekiq-con-outbox.md), [ADR-0022](../adr/0022-auditoria-append-only-e-idempotencia.md). Hitos: M0.10, M1.05, M3.03.

## El problema que resuelve el outbox

```ruby
ActiveRecord::Base.transaction do
  appointment.save!
end
NotifyJob.perform_later(appointment.id)   # ← si Redis falla aquí, la cita existe y el evento se perdió
```

Y al revés: si se encola **dentro** de la transacción y luego ocurre un rollback, el job procesa una cita que no existe. Con Sidekiq (Redis) no hay forma de que "guardar en PostgreSQL" y "encolar en Redis" sean atómicos. **Solución: escribir el evento en PostgreSQL, en la misma transacción, y publicarlo después.**

## Diseño

```
outbox_events
  id UUIDv7, organization_id, name, version, payload JSONB, metadata JSONB
  (actor, request_id, company_id, branch_id), occurred_at, published_at NULL, attempts, last_error
  INDEX (published_at) WHERE published_at IS NULL

processed_events
  consumer, event_id, processed_at
  PRIMARY KEY (consumer, event_id)
```

1. **Publicar:** `Events.publish("appointments.appointment_booked.v1", payload)` **solo inserta** en `outbox_events`, dentro de la transacción del caso de uso. Fuera de una transacción lanza un error (para no usarlo mal).
2. **Relay:** `Events::RelayJob` (sidekiq-cron cada 5 s, más un disparo tras el commit como optimización) toma lotes con `SELECT … FOR UPDATE SKIP LOCKED ORDER BY id LIMIT 100`, encola un `Events::DeliverJob` por suscriptor y marca `published_at`.
3. **Entregar:** `DeliverJob` reconstruye el contexto del tenant, verifica que el módulo del suscriptor esté activo para la empresa del evento, e invoca al suscriptor **dentro** de una transacción que inserta en `processed_events`. Si la clave ya existe, sale sin hacer nada (**idempotencia**).
4. **Reintentos:** los de Sidekiq con backoff exponencial; tras agotarlos, a la cola muerta con alerta en Sentry.

**Garantía:** entrega *al menos una vez* + consumidores idempotentes = efecto *exactamente una vez*. El orden se garantiza solo por agregado (UUIDv7 ordenado por tiempo); los consumidores no deben asumir un orden global.

## Contrato de eventos

- Nombre: `<modulo>.<hecho_en_pasado>.v<N>` → `appointments.appointment_rescheduled.v1`.
- Cada evento tiene un **esquema** (JSON Schema) en `packs/<pack>/app/public/<pack>/events/`. El payload se valida al publicar (en dev/test) y en CI.
- El payload lleva **IDs y datos mínimos necesarios**, nunca PII de más (el consumidor consulta lo que necesite por la API pública).
- Un cambio incompatible crea `v2` y conserva `v1` mientras haya suscriptores.

Eventos iniciales de `appointments`:

| Evento | Payload mínimo |
| --- | --- |
| `appointments.appointment_booked.v1` | `appointment_id, company_id, branch_id, customer_id, professional_id, starts_at, source` |
| `appointments.appointment_confirmed.v1` | `appointment_id` |
| `appointments.appointment_rescheduled.v1` | `appointment_id, new_appointment_id` |
| `appointments.appointment_cancelled.v1` | `appointment_id, cancelled_by, reason` |
| `appointments.appointment_completed.v1` | `appointment_id, services[], total_minor, currency` |
| `appointments.appointment_no_show.v1` | `appointment_id` |

Eventos de plataforma: `platform.organization_provisioned.v1`, `platform.module_enabled.v1`, `platform.module_disabled.v1`, `platform.customer_consent_changed.v1`.

## Jobs: reglas

| Regla | Motivo |
| --- | --- |
| Todo job recibe `organization_id` (y los ids que necesite) como argumento; un middleware de Sidekiq lo envuelve en `Tenancy.with_context` | Nunca hay un job sin tenant; RLS funciona igual que en requests |
| **Nunca leer `Current`** dentro de un job | `Current` es por request; en un job está vacío o es el de otro |
| Argumentos: IDs, nunca objetos serializados | El objeto puede cambiar entre el encolado y la ejecución |
| Todo job es idempotente | Sidekiq puede ejecutar dos veces |
| Colas: `critical` (relay, entregas), `default`, `notifications`, `low` (reportes, mantenimiento) | Que un envío masivo no frene el relay |

## Tareas programadas (escáneres)

Los recordatorios **no** se programan como jobs con días de anticipación (`perform_at(cita - 24h)`). Si la cita se reprograma o se cancela, ese job queda huérfano y envía un recordatorio falso.

En su lugar, un **escáner periódico** (sidekiq-cron, cada 5 min):

```
Appointments::ReminderScanJob
  para cada organización con el módulo activo:
    citas con starts_at en (ahora + ventana) y status ∈ (scheduled, confirmed)
    sin un reminder_dispatch para (appointment_id, kind)
  → crea reminder_dispatches(appointment_id, kind, idempotency_key) y llama a Notifications.deliver
```

- El estado actual de la cita **siempre** se consulta al momento de enviar.
- `UNIQUE (appointment_id, kind)` en `reminder_dispatches` impide los duplicados aunque dos escáneres se solapen.

Otros escáneres: limpieza de sesiones expiradas, purga de `processed_events` antiguos (> 30 días), purga de `outbox_events` publicados (> 30 días).

## Herramientas

- `sidekiq` + `sidekiq-cron` (o el scheduler de Sidekiq Enterprise si algún día se adquiere).
- La Sidekiq Web UI se monta solo para `PlatformStaff`, detrás de la autenticación de plataforma.
- Redis: base o namespace exclusivo para colas, separado del de rate limiting ([11](11-security.md)).
