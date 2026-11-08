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
