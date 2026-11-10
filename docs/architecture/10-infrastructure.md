# 10 — Infraestructura y operación

> Decisiones: [ADR-0002](../adr/0002-postgresql-18.md), [ADR-0013](../adr/0013-monorepo-y-mismo-origen.md). Hitos: M0.01, M0.02, M0.13, M4.04.

## Entornos

| Entorno | Para qué | Dónde | Datos |
| --- | --- | --- | --- |
| `development` | Desarrollo local | Docker Compose | Seeds de demo |
| `test` | CI y specs | GitHub Actions (servicios PG 18 + Redis) | Factories |
| `staging` | Demos, pruebas de despliegue y migraciones antes de producción | VPS (puede compartir host con producción al inicio, con una BD separada) | Seeds de demo + copias **anonimizadas** si hace falta |
| `production` | Pilotos y clientes | VPS | Reales |

> Staging no existía en los planes originales. Sin él, la primera vez que se prueba una migración contra datos reales es en producción.

## Desarrollo (M0.01)

- `docker compose up`, o `make up`, levanta: `db` (PG 18), `redis`, `api`, `worker`, `panel`, `booking`, `mailpit` y `proxy` (Caddy en `:8080`).
- **Mismo origen** desde el primer día: `/api` → api, `/c/*` → booking, `/` → panel.
- No requiere Ruby ni Node en el host.
- **Rutas:** el proxy **no** quita prefijos. Rails monta todo bajo `/api` y Vite sirve booking con `base: "/c/"`, de modo que desarrollo y producción coinciden. El websocket de HMR atraviesa el proxy (`server.hmr.clientPort` = puerto público).
- **Versiones fijadas (M0.01):** Ruby 3.4.12, Rails 8.1.4.1, Node 26.13.0, pnpm 12.18.0, PostgreSQL 18.6, Redis 7.4.12, Caddy 2.11.9, Mailpit 1.33.1 (también en `.tool-versions`).
- **Usuario no root** con el UID/GID del host (build args `HOST_UID`/`HOST_GID`, que `make up` rellena); `groupadd --non-unique` tolera un GID ya existente en la imagen (GID 20 en macOS).
- **Volúmenes con nombre:** `pg_data` (montado en `/var/lib/postgresql`, porque PostgreSQL 18 usa `/var/lib/postgresql/18/docker`), `redis_data`, `bundle` y `node_modules` (raíz, panel y booking). `node_modules` nunca se monta desde el host.
- **Orden de arranque:** `api` instala gems y corre `bin/setup` (idempotente) y `worker` espera a que esté `healthy`; `panel` instala el workspace de pnpm y `booking` espera a `panel`.
- **Base de datos:** `database.yml` lee `DB_HOST`, `APP_OWNER_PASSWORD`/`APP_USER_PASSWORD` y no `DATABASE_URL` (en test, `DATABASE_URL` sobrescribe el nombre de la base y apuntaría a desarrollo).
- **Puertos publicados:** solo el proxy (`8080`) y Mailpit (`8025`).
- **Verificación:** `make smoke` y `infra/scripts/hmr-check.sh`.

## CI (M0.02)

GitHub Actions; en cada PR:

| Job | Herramientas |
| --- | --- |
| Backend lint | RuboCop (rubocop-rails, rubocop-rspec), reglas custom (prohibir `without_tenant`, `admin?`, nombres de rol en policies) |
| Backend tests | RSpec con PostgreSQL 18 y Redis como servicios |
| Arquitectura | `packwerk check`, `packwerk validate`, sin crecimiento de `package_todo.yml` |
| Seguridad | `brakeman`, `bundler-audit`, `pnpm audit` (nivel alto) |
| Contrato | Regenerar OpenAPI y el cliente TS → falla si hay diff |
| Frontend | ESLint, `tsc --noEmit`, Vitest |
| E2E (en `main` y nightly) | Playwright sobre el stack de Compose (M0.12: job `e2e` solo en `main`, servicio `e2e` de Compose con imagen propia fijada; el *nightly* sigue pendiente) |
| Bundle de booking | Presupuesto de JS crítico < 150 KiB gzip (M0.12: job `frontend-bundle`) |
| Migraciones | `strong_migrations` + `db:migrate` desde cero + `db:rollback` de la última |

Rama `main` protegida; conventional commits; Dependabot mensual.

### Implementación (M0.02)

- **Jobs** (`.github/workflows/ci.yml`, en paralelo): `backend-lint`, **`backend-packs`** (`packwerk validate` + `check` y el guardián de `package_todo.yml`, con `fetch-depth: 0`), **`backend-migrations`** (migrar desde cero, rollback de la última, `structure.sql` sin diff; ver [09](09-data-conventions.md#migraciones)), `backend-test` (servicios `postgres:18.6-trixie` y `redis:7.4.12-alpine`; ambos jobs con BD instalan `postgresql-client-18` desde PGDG —el `pg_dump` del runner es el 16— y ejecutan `infra/db/init-roles.sh` para crear `app_owner`/`app_user`; `backend-migrations` es check requerido en `branch-protection.sh`), `backend-security`, `frontend-lint` (ESLint + Prettier + `tsc --noEmit`), `frontend-test`, **`frontend-security`** y **`api-contract`** (M0.06: regenera `backend/openapi/v1.yaml` con rswag y el cliente TS con openapi-typescript, y falla si difieren de lo versionado; servicios `postgres` y `redis` como `backend-test`; ver [07](07-api-contract.md#generación-del-contrato-y-del-cliente-typescript)) (`pnpm audit --audit-level=high`; se separó de `frontend-lint` para que un aviso de seguridad no se confunda con un fallo de estilo). Otro workflow, `pr-title.yml`, valida el título del PR. `branch-protection.sh` exige como checks todos los jobs de `ci.yml` (incluidos `frontend-bundle` y `e2e`) más `pr-title`.
- **Una sola definición de cada paso:** los jobs llaman a `backend/bin/ci-*` y `frontend/bin/ci-*`; `bin/ci` (o `make ci`) llama a los mismos scripts en los contenedores de desarrollo. `infra/scripts/check-versions.sh` verifica que `.tool-versions`, los Dockerfiles, `compose.yaml`, `package.json` y `ci.yml` usen las mismas versiones.
- **Cachés:** gemas (`ruby/setup-ruby` con `bundler-cache`, por `Gemfile.lock`) y store de pnpm (`actions/setup-node` con `cache: pnpm`).
- **Acciones fijadas por SHA de commit** (con la versión en un comentario); Dependabot (`github-actions`) las actualiza cada mes. Trampa: en tags anotados `git ls-remote` lista primero el SHA del objeto tag; el commit es la línea `refs/tags/<tag>^{}`. `infra/scripts/check-action-pins.sh` (en `repo-checks` y en `backend-lint`) valida el formato offline y, con red, contrasta cada SHA con el remoto (`ONLINE=0` para omitirlo). Se detectó así `pnpm/action-setup`.
- **Job `actionlint`:** valida los workflows con la misma imagen Docker fijada que usa `bin/ci`.
- **Título del PR:** `infra/scripts/check-pr-title.sh` es la única definición de la regla (tipos `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`, ámbito opcional, `!` opcional) y tiene pruebas (`check-pr-title_test.sh`). Dependabot usa los prefijos `chore(deps)` y `ci(deps)` para cumplirla.
- **Sin archivos grandes en git:** `infra/scripts/check-large-files.sh` (en `repo-checks` y en `backend-lint`, con `fetch-depth: 0` y `BASE_REF` como el guardián de `package_todo.yml`) falla si la rama agrega un binario de más de 100 KiB o cualquier archivo de más de 1 MiB. Revisa **cada blob que la rama introduce** desde el merge-base, no solo el árbol final: un binario agregado y borrado en la misma rama queda en el historial para siempre (los merges son `--no-ff`). Capturas, videos y evidencia de QA van adjuntos al PR; `frontend/e2e/screenshots/` está gitignorado. Excepciones en `infra/scripts/large-files-allowlist.txt` (`<glob> | <motivo>`, motivo obligatorio). 17 casos en `check-large-files_test.sh`. Al crearlo (2026-11-10) el repo no tenía ningún binario y el archivo más grande de su historia era `pnpm-lock.yaml` (220 KiB).
- **Rama protegida:** `infra/github/branch-protection.sh <owner>/<repo>` (simulación por defecto, `APPLY=1` para aplicar) exige los checks de todos los jobs de `ci.yml` (`actionlint` y `api-contract` incluidos) más `pr-title` (publicados por GitHub Actions: `app_id` 15368), ramas al día (`strict`), historial lineal, conversaciones resueltas y administradores incluidos. Ajuste manual: solo *squash merge* con el título del PR como mensaje.
- **TypeScript 7 y typescript-eslint:** `typescript-eslint` 8.72 aún no soporta TS 7 (aborta al cargar). `packages/config` instala `typescript@6.0.3` solo para él (pnpm resuelve el peer por paquete); `tsc`, Vite y Vitest de las apps siguen con TS 7.0.2. Volver a una sola versión cuando typescript-eslint soporte TS >= 7.1. **`packages/api-client` (M0.06) también fija `typescript@6.0.3`**: `openapi-typescript` 7.13 usa la API programática de TypeScript (`ts.factory`) y con TS 7 falla con `Cannot read properties of undefined (reading 'createKeywordTypeNode')`; volver a una sola versión cuando openapi-typescript soporte TS 7. Dependabot no permite ignorar por paquete del workspace: `dependabot.yml` descarta para `typescript` las subidas `>=6.1.0 <7.0.0` y los saltos mayores (6.0.3 -> 7 en `packages/config`), mientras que menores y parches de TS 7.x (apps) siguen llegando. Quitar ese `ignore` junto con el pin.
- **`node_modules` de `packages/config` y de `packages/api-client`** son otros volúmenes con nombre (`config_node_modules`, `api_client_node_modules`), igual que los de las apps. El contenedor del frontend monta además `backend/openapi` en `/app/backend/openapi` **de solo lectura**: el cliente TS se genera desde ahí (en CI la ruta relativa `../../../backend/openapi/v1.yaml` es la misma).

## Producción (M4.04)

```
Internet → kamal-proxy (TLS Let's Encrypt) → contenedores
             ├── web     (Rails + estáticos de panel y booking)
             ├── worker  (Sidekiq)
             └── accesorios: PostgreSQL 18, Redis
```

- **Kamal 2**: imagen multi-etapa (build de las apps de frontend + gems), deploy sin downtime y rollback con un comando.
- **Estáticos de frontend:** el build de `panel` y `booking` se sirve desde el mismo origen. Opciones a decidir en M4.04: (a) Rails/Thruster sirviendo `public/` con fallback SPA por prefijo, o (b) un contenedor de estáticos con enrutamiento por ruta en el proxy. Criterio: mantener **un solo origen** y cabeceras de caché correctas (assets con hash → inmutables; `index.html` → sin caché).
- **Secretos:** `kamal secrets` (desde un gestor de contraseñas), Rails credentials por entorno. Nada en el repo.
- **Variables obligatorias en producción y staging:** `APP_ORIGINS` (orígenes permitidos para la validación de `Origin` en mutaciones, separados por comas; sin ella toda mutación con `Origin` se rechaza — falla cerrado, ver [11 §CSRF](11-security.md)). Además `AR_ENCRYPTION_PRIMARY_KEY`, `AR_ENCRYPTION_DETERMINISTIC_KEY` y `AR_ENCRYPTION_KEY_DERIVATION_SALT` (Active Record Encryption; sin ellas `encrypts` falla cerrado, ver [09](09-data-conventions.md#datos-personales-pii)). La lista completa se consolida en M4.04.
- **Migraciones en deploy:** ejecutadas por Kamal antes de cambiar el tráfico; deben ser compatibles hacia atrás (expand/contract) para permitir rollback.

### Base de datos: gestionada vs autogestionada (decisión pendiente para M4.04)

| | Autogestionada en el VPS | Gestionada (DigitalOcean, Crunchy Bridge, Neon, RDS…) |
| --- | --- | --- |
| Costo mensual | Bajo | Medio a alto |
| Backups y PITR | Los configuras tú (WAL-G a S3/R2) | Incluidos |
| Actualizaciones mayores | Tú (`pg_upgrade`) | Asistidas |
| Réplica y failover | Manual | Opción del proveedor |
| Requisito | RLS, `btree_gist` y PG 18 disponibles | **Verificar** que el proveedor ofrezca PG 18 y las extensiones necesarias |

Se decide en M4.04 con costos reales. El código no cambia en ningún caso.

### Backups

- **WAL-G** (si es autogestionada): backup base diario + archivado continuo de WAL a object storage (S3/R2) → **PITR** (restauración a un punto en el tiempo).
- Cifrado en reposo en el bucket; credenciales de solo escritura para el servidor.
- Retención: 30 días de PITR y 12 backups mensuales.
- **Simulacro de restauración trimestral**, documentado con tiempos. Un backup que nunca se restauró no es un backup.
- ActiveStorage en el mismo proveedor de objetos, con versionado del bucket.

## Observabilidad (M0.13)

| Pieza | Detalle |
| --- | --- |
| Logs | JSON estructurado, **una línea por request y por job**, con `request_id`, `organization_id`, `company_id`, `branch_id`, `principal_type`, `principal_id`, duración y status. Sin PII |
| Errores | Sentry (backend, worker y panel), con tags de tenant y `release` |
| Salud | `/api/health` (proceso vivo, sin BD) y `/api/ready` (PG + Redis) |
| Uptime | Monitor externo sobre `/api/health` y `/c/<slug-demo>` |
| Métricas | Fase inicial: Sidekiq (colas, latencia, muertos), `pg_stat_statements`, tamaño del outbox pendiente. **Alerta a Sentry si el outbox sin publicar supera 5 min** (`Events::OutboxLagAlert`) |
| Retención de logs | 90 días |

### Logs: lograge + formateador JSON propio

**Decisión: lograge, no `rails_semantic_logger`.** Aquí solo hacen falta una línea por request y por job con campos fijos; Semantic Logger sustituye todo el logger de Rails y trae su propio hilo de escritura, más superficie de la que se necesita. Lograge (`0.15.1`, fijada) condensa el log de la acción y `Observability::JsonLogFormatter` serializa **todas** las entradas del logger de Rails como una línea JSON (`ts`, `level` y, según el caso, `msg` o los campos aplanados).

Línea de una request (`config/initializers/structured_logging.rb`):

```json
{"ts":"2026-11-09T20:03:45.462Z","level":"INFO","method":"GET","path":"/api/v1/auth/session","format":"*/*","controller":"Api::V1::Identity::SessionsController","action":"show","status":401,"allocations":12208,"duration":14.72,"view":0.07,"db":0.0,"organization_id":null,"company_id":null,"branch_id":null,"principal_type":null,"principal_id":null,"request_id":"7ffbb6d8-…","remote_ip":"172.22.0.1"}
```

- `duration` es en **milisegundos**. `path` va **sin query string** y los **parámetros no se registran** (el filtro de `filter_parameters` es una red de seguridad, no una autorización). `/api/health` y `/api/ready` no generan línea.
- Los campos de tenant y principal salen de `Observability::LogFields`, que lee `Current.context` y `Current.principal` de forma **genérica** (tipo del principal = nombre de su clase en snake_case, o su `principal_type` si lo define): cuando M0.08 traiga `Access::Principal` y el contexto por ruta no hay que tocar nada.
- **El contexto se «recuerda».** La línea se escribe al terminar la acción, cuando un `around_action` con `Tenancy.with_context` ya salió y `Current.context` volvió a `nil`; y un job que lanza una excepción la propaga fuera del contexto antes de que Sentry la capture. `Observability::TenancyHook` (antepuesto a `Tenancy` en `to_prepare`, sin editar el pack) deja la organización/empresa/sucursal del **último** `with_context` abierto en `Observability::LogContext` (`CurrentAttributes`; Rails lo reinicia por request y por job). Si una acción abre varios contextos seguidos se registra el último.
- **`request_id` y `remote_ip` salen de `Current`** (`Api::RequestMetadata`, M0.11): son los mismos que anota la auditoría, y `Current.ip` ya sale de `request.remote_ip` saneado por `NetworkTrust` (spec: login con `Forwarded`/`X-Real-IP` falsos → log y `Audit::AuthEvent` con la IP del par). Sentry los etiqueta con `request_id`. Si la request no llegó a ese `before_action`, se usan los de la propia request.
- **Una sola fuente por línea:** con contexto vivo se usa solo `Current.context`; sin él, solo el recordado (nunca una mezcla). `principal_id` puede ser `nil` (principal del sistema) y `principal_type` sale de `principal_type`, `actor_type` (contrato de M0.11, p. ej. `Access::Principal::User` → `user`), `kind` o el nombre de la clase.
- **SQL fuera del log de desarrollo:** el SQL se registra en `debug` con los valores como literales (`WHERE email = '…'`, PII en claro), así que desarrollo arranca en `info`; `RAILS_LOG_LEVEL=debug` lo reactiva a conciencia. Sin códigos de color ANSI (romperían el JSON). El log interno del SDK de Sentry también sale por el logger de Rails. Quedan en texto plano solo los banners de Puma y de `bin/setup`.
- Producción ya **no** usa `config.log_tags = [:request_id]`: el prefijo `[id]` rompe el JSON; el `request_id` es un campo.
- **Jobs de Sidekiq** (`config/middleware/job_observability.rb`): mismo esquema aplanado — `ts`, `level`, `pid`, `tid`, `msg` (`start`/`done`/`fail`), `job_class`, `jid`, `organization_id` (del payload), `duration` (ms), `company_id`, `branch_id`, `principal_type`, `principal_id` —, **nunca** los argumentos. Toda línea del logger de Rails emitida dentro de un job lleva además `jid`, `job_class` y `organization_id`. `JobLogger` deja `organization_id` y `job_class` en `Observability::LogContext` para Sentry.
- `filter_parameters` (`config/initializers/filter_parameter_logging.rb`): contraseña (`passw`, `contrase`), `token`, `otp`, correo (`email`, `correo`), teléfono (`phone`, `telefono`, `teléfono`, `celular`, `mobile`, `whatsapp`), `csrf`, `authorization`, `cookie`, más los genéricos de Rails (`secret`, `_key`, `crypt`, `salt`, `certificate`, `ssn`, `cvv`, `cvc`). Coincidencia parcial de la clave.
- Pendiente de revisar al cerrar el hito (riesgo de la ficha): una muestra de logs reales buscando PII de gemas de terceros; el resultado está en las notas de cierre de M0.13.

### Sentry

Backend y worker: `sentry-ruby`, `sentry-rails` y `sentry-sidekiq` `7.2.0` (fijadas). Panel: `@sentry/react` `11.11.0`. Configuración en `config/middleware/sentry_setup.rb` (backend) y `frontend/apps/panel/src/sentry.ts`.

| Variable | Dónde | Efecto |
| --- | --- | --- |
| `SENTRY_DSN` | backend y worker | Sin ella Sentry queda inactivo (desarrollo, CI). **En test siempre inactivo**, aunque haya DSN |
| `SENTRY_ENVIRONMENT` | backend y worker | Nombre del entorno en Sentry (`production`, `staging`); por defecto `Rails.env` |
| `APP_RELEASE` | backend y worker | `release` (p. ej. el SHA del commit). El mismo valor va a `VITE_APP_RELEASE` del panel |
| `VITE_SENTRY_DSN`, `VITE_SENTRY_ENVIRONMENT`, `VITE_APP_RELEASE` | panel (se fijan al construir) | Ídem para el navegador. Inactivo sin DSN y en modo `test` |

- **Sin PII:** backend con `send_default_pii = false` (en Sentry 7 equivale a `data_collection` restrictivo: sin cuerpos, cookies, usuario ni IP) y panel con `dataCollection` explícito en off. `before_send` además quita correos de los mensajes, filtra los datos extra con `config.filter_parameters` y retira los `args` de los jobs. Los mensajes de excepción pueden contener otros datos que no se pueden detectar: no pongas secretos en mensajes de error.
- **Tags de cada evento** (un procesador global de eventos, `SentrySetup.install_event_processor`, que corre SÍNCRONO al capturar: `before_send` corre en el hilo de fondo del cliente de Sentry, donde `Current` y `LogContext` están vacíos, y solo limpia datos): `organization_id`, `company_id`, `branch_id`, `principal_type`, `principal_id` (solo identificadores) y, en jobs, `job` (la clase). En un job el error se captura FUERA de `JobLogger#prepare` (Sidekiq llama a `handle_exception` después), así que la organización y la clase se leen del contexto `sidekiq` que sentry-sidekiq adjunta con el job. `release` y `environment` van en el propio evento.
- **500 de la API:** `Api::ErrorHandling` rescata todo y responde problem+json, así que el middleware de Rack de Sentry nunca ve la excepción. Llega por `Rails.error.report` (`Api::ErrorReporter`), al que Sentry se suscribe (`register_error_subscriber = true`; viene en `false` por defecto: sin ello los 500 no se reportarían). Solo `internal.error` se reporta; los 4xx no.
- **Verificación manual** (necesita un DSN real): `SENTRY_DSN=… bin/rails sentry:test[ORGANIZATION_ID]` envía un error con `organization_id` y encola `Observability::SentryTestJob`, que siempre falla (el **worker** también debe tener el DSN). En Sentry deben aparecer ambos con el tag `organization_id` (y `job` el del job). Para el panel, lanzar un error no capturado con `VITE_SENTRY_DSN` definido.
- **Alerta del lag del outbox:** `Events::OutboxLagAlert` se suscribe a `outbox_lag.events` (la emite `Events::OutboxLagJob` cada minuto) y, si el evento pendiente más antiguo supera `OUTBOX_LAG_ALERT_SECONDS` (300 por defecto), reporta `Events::OutboxLagExceeded` con `Rails.error` (severidad `error`, contexto `pending`, `oldest_age_seconds`, `threshold_seconds`). El mensaje es fijo para que Sentry agrupe todas las alertas en una incidencia; mientras dure el atasco habrá un reporte por minuto.

### Proxy y red

- **IP real del cliente.** `trusted_proxies` conserva el valor por defecto de Rails (loopback y rangos privados 10/8, 172.16/12, 192.168/16, fc00::/7), que cubre el Caddy de compose y kamal-proxy en el mismo host; `TRUSTED_PROXIES` (CIDR separados por comas) **añade** rangos en desarrollo y test (la IP del Caddy de compose cambia) y **sustituye** los rangos privados en producción, para estrechar la confianza a la IP de kamal-proxy (sin la variable se conservan los de Rails). Un rango inválido falla al arrancar. **Gotcha descubierto en M0.13:** Rails usa `X-Forwarded-For` aunque la conexión NO venga de un proxy de confianza, así que quien llegue directo a la app podía falsear su IP y esquivar el límite por IP; `NetworkTrust::UntrustedForwardingFilter` (antes de `RemoteIp`) borra SIEMPRE `Forwarded` (RFC 7239, que Rails 8.1 también lee), `Client-IP` y `X-Real-IP`, y `X-Forwarded-For` si el par directo no es un proxy de confianza; Caddy también las retira de lo que reenvía a la API (`header_up -Forwarded -Client-Ip -X-Real-Ip`). Sin eso un `Client-IP` contradictorio provocaba un `IpSpoofAttackError` (500) antes de llegar a `ShowExceptions`. El proxy de borde debe **sobrescribir** `X-Forwarded-For` (Caddy lo hace por defecto) y la app solo debe ser alcanzable a través de él: en la red de compose cualquier contenedor es un «proxy de confianza» (red privada). Evidencia en las notas de cierre de M0.13.
- **`config.hosts`** (pendiente anotado en 11): en **producción y staging** se derivan de `APP_ORIGINS` (los mismos orígenes que valida `Origin`; si la lista está vacía no se restringe, y las mutaciones ya fallan cerradas). `/api/health` y `/api/ready` se excluyen de la comprobación (un healthcheck llama por IP interna). Desarrollo y test no cambian: Rails ya acepta `localhost` y compose llama a `api:3000`. La lista definitiva de variables se consolida en M4.04.
- **Cabeceras de seguridad:** `SecurityHeaders` (primer middleware: cubre también los 4xx de otros middlewares). Ver [11 §Transporte y cabeceras](11-security.md#transporte-y-cabeceras).
- **CSP del panel:** el proxy (Caddy) envía `Content-Security-Policy-Report-Only` en la ruta del panel. En desarrollo Vite inyecta scripts en línea y usa websockets, así que la consola del navegador lista violaciones esperables; se endurece y pasa a `Content-Security-Policy` con el build de producción (M4.04).

## Runbooks (se escriben en M4.04)

- Restaurar la BD a un punto en el tiempo.
- Rotar secretos: BD, Redis, Meta, claves de cifrado y firma.
- Reprocesar la cola muerta de Sidekiq.
- Revocar todas las sesiones de un usuario u organización.
- Activar o desactivar un módulo para una empresa desde la consola.
- Modo mantenimiento.
