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
outbox_events          (tabla TENANT: organization_id NOT NULL, FK, política tenant_isolation)
  id UUIDv7, organization_id, name ("platform.organization_provisioned.v1": la versión va dentro del nombre),
  payload JSONB, metadata JSONB (company_id, branch_id y lo que aporte el llamador),
  occurred_at, published_at NULL, attempts, last_error, created_at, updated_at
  CHECK name ~ '^<modulo>.<hecho>.v<N>$'
  INDEX (id) WHERE published_at IS NULL            -- lo que recorre el relay
  INDEX (published_at) WHERE published_at IS NOT NULL  -- purga

processed_events       (tabla TENANT)
  id, organization_id, event_id, subscriber, processed_at
  UNIQUE (event_id, subscriber)                    -- la clave de la idempotencia
  INDEX (processed_at)                             -- purga
```

Ambas son tablas tenant: todo evento pertenece a una organización, el suscriptor corre en su contexto y entran solas en la suite de aislamiento. Sin FK entre ellas: la purga de cada una es independiente. El `UNIQUE (event_id, subscriber)` sustituye a la `PRIMARY KEY (consumer, event_id)` prevista originalmente (las tablas tenant tienen `id` uuid).

1. **Publicar:** `Events.publish("appointments.appointment_booked.v1", { appointment_id: ... })` (o con argumentos con nombre) **solo inserta** en `outbox_events`, dentro de la transacción del caso de uso y con la organización del contexto. Valida el payload contra su esquema (siempre, no solo en test): sin esquema `Events::UnknownEvent`, payload inválido `Events::InvalidPayload` con el detalle; fuera de una transacción `Events::NotInTransaction`. Tras el `COMMIT` dispara un `RelayJob` (optimización, `Events::RelayKick`): **uno solo por transacción** aunque se publiquen varios eventos, y si Redis falla se registra un aviso y se hace una pausa de 5 s sin reintentar (así un Redis caído no añade la espera del timeout a cada COMMIT); el cron es la red de seguridad. `metadata:` se mezcla con la empresa y sucursal del contexto; el actor y el `request_id` llegarán con la sesión (M0.07).
2. **Relay:** `Events::RelayJob` (sidekiq-cron cada ~5 s) llama a `Events::Relay`: por lote de 100, en una transacción, `SELECT … ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED`, encola un `Events::DeliverJob` por (evento, suscriptor) con `push_bulk` agrupado por organización y cola, y marca `published_at`. Si Redis falla la transacción se revierte, el evento sigue pendiente y se anotan `attempts` y `last_error`; el job reporta el error al *error reporter* de Rails y no reintenta (lo hace el cron en 5 s).
3. **Entregar:** `DeliverJob(event_id, subscriber)` se ejecuta con el `organization_id` en su payload, o sea dentro de `Tenancy.with_context` (middleware de [03](03-multi-tenancy.md)), carga el evento (`find` acotado al tenant: un evento de otra organización es `RecordNotFound`), inserta la marca en `processed_events` **antes** de invocar al suscriptor y en la misma transacción. Si la marca ya existe (`RecordNotUnique`) sale sin hacer nada (**idempotencia**, también con dos workers simultáneos: el segundo espera al `COMMIT` del primero). Si el suscriptor lanza, se revierte todo —marca incluida— y Sidekiq reintenta. **Pendiente de M0.09:** verificar que el módulo del suscriptor esté activo para la empresa del evento.
4. **Reintentos:** los de Sidekiq con backoff exponencial; tras agotarlos, a la cola muerta con alerta en Sentry. Los errores que reintentar no arregla van **directo a la cola muerta**, sin los ~21 días de reintentos: un job sin `organization_id` o de una organización inexistente (middleware) y un suscriptor no registrado (`Events::UnknownSubscriber`, `sidekiq_retry_in` → `:kill`).

**Límite de la guarda `NotInTransaction`:** comprueba `transaction_open?`, que es verdadero en cualquier transacción, también la que abren las fixtures transaccionales de los specs, y `Tenancy.with_context` (que siempre abre una). No prueba que sea *la transacción del caso de uso*: publicar desde un `with_context` abierto solo para eso pasa la guarda. Es una red contra el olvido, no una prueba de atomicidad; la disciplina de publicar junto al cambio de datos es del caso de uso. Los specs de "fuera de transacción" y de rollback no usan fixtures transaccionales.

**Garantía:** entrega *al menos una vez* + consumidores idempotentes = efecto *exactamente una vez*. **No hay orden garantizado**, ni siquiera por agregado: el relay publica por `id` (UUIDv7, aproximadamente cronológico), pero los `DeliverJob` se ejecutan en paralelo, se reintentan de forma independiente y pueden llegar desordenados. Los consumidores toleran el desorden (p. ej. comparan el estado actual consultando por ID, no asumen que `rescheduled` llega después de `booked`). Si Redis acepta parte de un lote y luego falla el `COMMIT`, el reintento vuelve a encolar esos jobs: de ahí la idempotencia.

### El relay es un camino privilegiado

El relay, las purgas y la medición del lag leen `outbox_events` de **todas** las organizaciones. Esa lectura vive en **un único archivo**, `Events::CrossTenant` (`app/services/events/cross_tenant.rb`), el único con `ActsAsTenant.without_tenant`, y está en `AllowedFiles` del cop `Ceiba/TenantBypass` (revisión de CODEOWNERS). Solo **lee o borra** del propio outbox: las escrituras de estado (`published_at`, `attempts`, `last_error`) se hacen **organización por organización dentro de `Tenancy.with_context`**, así pasan por el guard de escritura. Con RLS (M4.03) estas lecturas necesitarán el rol de plataforma con `BYPASSRLS` (queda como tarea de M4.03).

### Suscriptores

```ruby
Events.subscribe("platform.organization_provisioned.v1", as: "notifications.welcome", queue: "notifications") do |event|
  # event es un Events::Event (id, name, organization_id, payload, metadata, occurred_at)
  # Corre dentro del contexto de tenant del evento y de una transacción.
end
```

`as:` identifica al suscriptor y es la clave de la idempotencia: **renombrarlo equivale a un suscriptor nuevo** (los eventos ya procesados por el nombre viejo se volverían a entregar al nuevo). Para renombrar, conserva el nombre anterior o acepta la re-entrega con un handler idempotente.  la cola por defecto es `critical`. El registro vive en `config.x.events` (no en la clase, que se recarga) y registrar el mismo (evento, suscriptor) lo **reemplaza**, así se registra desde `config.to_prepare` de forma idempotente.

## Contrato de eventos

- Nombre: `<modulo>.<hecho_en_pasado>.v<N>` → `appointments.appointment_rescheduled.v1`.
- Cada evento tiene un **esquema** (JSON Schema, `json_schemer` 2.5.0) en `packs/<capa>/<pack>/app/public/<pack>/events/<nombre del evento>.json`: el nombre del archivo ES el nombre del evento y `Events::Schemas` los carga todos. El payload se valida al publicar (siempre) y la suite de eventos de plataforma lo comprueba en CI.
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

Eventos de plataforma:

| Evento | Estado |
| --- | --- |
| `platform.organization_provisioned.v1` | Emitido por `Events::ProvisioningHook` (hook de `ProvisionOrganization`, M0.10). Payload: `organization_id, company_id, branch_id` |
| `platform.module_enabled.v1`, `platform.module_disabled.v1` | **Esquema registrado, sin emisor**: `Modules::Enable`/`Disable` llegan en M0.09, que los emitirá y confirmará el payload (provisional: `company_id, module`) |
| `platform.customer_consent_changed.v1` | Sin esquema todavía (M3.01) |

## Jobs: reglas

| Regla | Motivo |
| --- | --- |
| El `organization_id` viaja en el **payload** del job (lo añade el middleware de cliente al encolar) y el middleware de servidor lo envuelve en `Tenancy.with_context`; un job sin él no corre. Los jobs del sistema declaran `sidekiq_options tenant: false` | Nunca hay un job tenant sin tenant; RLS funciona igual que en requests |
| **Nunca leer `Current`** dentro de un job | `Current` es por request; en un job está vacío o es el de otro |
| Argumentos: IDs, nunca objetos serializados | El objeto puede cambiar entre el encolado y la ejecución |
| Todo job es idempotente | Sidekiq puede ejecutar dos veces |
| Colas (pesos en `config/sidekiq.yml`): `critical` 6 (relay, entregas), `default` 3, `notifications` 2, `low` 1 (reportes, mantenimiento, purgas) | Que un envío masivo no frene el relay |

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

Otros escáneres: limpieza de sesiones expiradas.

### Tareas del pack `events` (M0.10)

Se registran en `Events::Schedule` al arrancar Sidekiq (`config/initializers/sidekiq_cron.rb`); todas son jobs del sistema (`tenant: false`).

| Job | Cron | Cola | Qué hace |
| --- | --- | --- | --- |
| `Events::RelayJob` | `*/5 * * * * *` (cada 5 s) | critical | Publica el outbox |
| `Events::OutboxLagJob` | cada minuto | default | Mide el lag: `events.outbox_lag pending=N oldest_age_seconds=S` en el log y la notificación `outbox_lag.events` (la alerta de > 5 min se conecta en M0.13) |
| `Events::PurgeOutboxJob` | 03:17 UTC | low | Borra `outbox_events` **publicados** hace más de 30 días, por lotes de 1000; nunca un pendiente |
| `Events::PurgeProcessedJob` | 03:27 UTC | low | Borra `processed_events` de más de 30 días, por lotes |

El cron de segundos exige un poll de sidekiq-cron menor que el intervalo (`cron_poll_interval = 1`, el defecto es 30): medido con el worker real, el relay arranca cada 4-6 s.

## Herramientas

- `sidekiq` 8.1 + `sidekiq-cron` 2.4.0 (o el scheduler de Sidekiq Enterprise si algún día se adquiere).
- La Sidekiq Web UI **no está expuesta** (un spec lo vigila): se monta solo para `PlatformStaff`, detrás de la autenticación de plataforma, en M4.01.
- Redis: base o namespace exclusivo para colas, separado del de rate limiting ([11](11-security.md)).

## Pruebas

- **Suite de eventos de plataforma** ([12 §6](12-testing-strategy.md)): `spec/platform/events/events_suite_spec.rb` descubre los eventos publicados en el código (deben tener esquema), los suscriptores registrados (evento con esquema, cola declarada) y ejecuta sobre cada suscriptor de cualquier pack el ejemplo compartido `"un suscriptor idempotente"` (`spec/support/event_subscriber_examples.rb`): entregado dos veces, un solo efecto. Un pack nuevo entra solo.
- **Integración con Redis real** (`packs/platform/events/spec/integration/outbox_redis_spec.rb`, etiqueta `:redis`: `Sidekiq.testing!(:disable)` y `flushdb`; COMMIT real): Redis caído y vuelve, dos relays concurrentes con 500 eventos, dos workers con el mismo job. Los demás specs corren con Sidekiq en modo `fake`.
- "Redis caído" se simula apuntando el cliente a un puerto cerrado (`Sidekiq::Client.via`): es el mismo fallo (`RedisClient::CannotConnectError`) que ve la aplicación con el contenedor detenido. La prueba con el contenedor real está en las notas de cierre de M0.10.
- **Redis de test:** `config/initializers/redis.rb` fuerza la base **15** en `RAILS_ENV=test`, gane o no `REDIS_URL` (compose da la base 0 a todos los contenedores, también al worker de desarrollo, que si no consumiría los jobs de la suite). Los specs `:redis` se niegan a hacer `flushdb` si la conexión no es la 15 y el cron de desarrollo (base 0) no se toca.
- **Base de datos de test:** `database.yml` pone `seeds: false` en test: Rails 8.1 siembra la base cuando `db:prepare` la crea vacía (como en el job `backend-test` de CI) y los specs asumen cero organizaciones.
