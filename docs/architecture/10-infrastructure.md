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
- **Base de datos:** `database.yml` lee `DB_HOST`/`POSTGRES_*` y no `DATABASE_URL` (en test, `DATABASE_URL` sobrescribe el nombre de la base y apuntaría a desarrollo).
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
| E2E (en `main` y nightly) | Playwright sobre el stack de Compose |
| Migraciones | `strong_migrations` + `db:migrate` desde cero + `db:rollback` de la última |

Rama `main` protegida; conventional commits; Dependabot mensual.

### Implementación (M0.02)

- **Jobs** (`.github/workflows/ci.yml`, en paralelo): `backend-lint`, **`backend-packs`** (`packwerk validate` + `check` y el guardián de `package_todo.yml`, con `fetch-depth: 0`), `backend-test` (servicios `postgres:18.6-trixie` y `redis:7.4.12-alpine`), `backend-security`, `frontend-lint` (ESLint + Prettier + `tsc --noEmit`), `frontend-test` y **`frontend-security`** (`pnpm audit --audit-level=high`; se separó de `frontend-lint` para que un aviso de seguridad no se confunda con un fallo de estilo). Otro workflow, `pr-title.yml`, valida el título del PR.
- **Una sola definición de cada paso:** los jobs llaman a `backend/bin/ci-*` y `frontend/bin/ci-*`; `bin/ci` (o `make ci`) llama a los mismos scripts en los contenedores de desarrollo. `infra/scripts/check-versions.sh` verifica que `.tool-versions`, los Dockerfiles, `compose.yaml`, `package.json` y `ci.yml` usen las mismas versiones.
- **Cachés:** gemas (`ruby/setup-ruby` con `bundler-cache`, por `Gemfile.lock`) y store de pnpm (`actions/setup-node` con `cache: pnpm`).
- **Acciones fijadas por SHA de commit** (con la versión en un comentario); Dependabot (`github-actions`) las actualiza cada mes. Trampa: en tags anotados `git ls-remote` lista primero el SHA del objeto tag; el commit es la línea `refs/tags/<tag>^{}`. `infra/scripts/check-action-pins.sh` (en `repo-checks` y en `backend-lint`) valida el formato offline y, con red, contrasta cada SHA con el remoto (`ONLINE=0` para omitirlo). Se detectó así `pnpm/action-setup`.
- **Job `actionlint`:** valida los workflows con la misma imagen Docker fijada que usa `bin/ci`.
- **Título del PR:** `infra/scripts/check-pr-title.sh` es la única definición de la regla (tipos `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`, ámbito opcional, `!` opcional) y tiene pruebas (`check-pr-title_test.sh`). Dependabot usa los prefijos `chore(deps)` y `ci(deps)` para cumplirla.
- **Rama protegida:** `infra/github/branch-protection.sh <owner>/<repo>` (simulación por defecto, `APPLY=1` para aplicar) exige los 8 checks (`actionlint` incluido, publicados por GitHub Actions: `app_id` 15368), ramas al día (`strict`), historial lineal, conversaciones resueltas y administradores incluidos. Ajuste manual: solo *squash merge* con el título del PR como mensaje.
- **TypeScript 7 y typescript-eslint:** `typescript-eslint` 8.72 aún no soporta TS 7 (aborta al cargar). `packages/config` instala `typescript@6.0.3` solo para él (pnpm resuelve el peer por paquete); `tsc`, Vite y Vitest de las apps siguen con TS 7.0.2. Volver a una sola versión cuando typescript-eslint soporte TS >= 7.1. Dependabot no permite ignorar por paquete del workspace: `dependabot.yml` descarta para `typescript` las subidas `>=6.1.0 <7.0.0` y los saltos mayores (6.0.3 -> 7 en `packages/config`), mientras que menores y parches de TS 7.x (apps) siguen llegando. Quitar ese `ignore` junto con el pin.
- **`node_modules` de `packages/config`** es otro volumen con nombre (`config_node_modules`), igual que los de las apps.

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
| Logs | JSON estructurado (lograge o rails_semantic_logger) con `request_id`, `organization_id`, `company_id`, `branch_id`, `principal_type`, `principal_id`, duración y status. Sin PII |
| Errores | Sentry (backend y frontend), con tags de tenant y release |
| Salud | `/api/health` (proceso vivo, sin BD) y `/api/ready` (PG + Redis) |
| Uptime | Monitor externo sobre `/api/health` y `/c/<slug-demo>` |
| Métricas | Fase inicial: Sidekiq (colas, latencia, muertos), `pg_stat_statements`, tamaño del outbox pendiente. Alerta si el outbox sin publicar supera 5 min |
| Retención de logs | 90 días |

## Runbooks (se escriben en M4.04)

- Restaurar la BD a un punto en el tiempo.
- Rotar secretos: BD, Redis, Meta, claves de cifrado y firma.
- Reprocesar la cola muerta de Sidekiq.
- Revocar todas las sesiones de un usuario u organización.
- Activar o desactivar un módulo para una empresa desde la consola.
- Modo mantenimiento.
