# Ceiba

Ecosistema modular y multi-tenant para negocios de servicios en Nicaragua: clínicas, salones, barberías y consultorios. El primer módulo es **Ceiba Citas**.

- Documentación (fuente única de verdad): [`docs/`](docs/README.md)
- Hoja de ruta y estado: [`docs/roadmap/`](docs/roadmap/README.md)
- Decisiones de arquitectura: [`docs/adr/`](docs/adr/README.md)
- Infraestructura y operación: [`docs/architecture/10-infrastructure.md`](docs/architecture/10-infrastructure.md)
- Planes originales (históricos): [`plans/`](plans/)

## Requisitos

Solo **Docker** (Engine 24+ con Compose v2.20+, o Docker Desktop) y **Git**. No hace falta Ruby, Node ni pnpm en tu máquina: todo corre en contenedores.

Para quien prefiera instalar las herramientas a mano, las versiones fijadas están en [`.tool-versions`](.tool-versions).

## Arranque

```sh
git clone <url-del-repo> ceiba && cd ceiba
make up          # equivale a: docker compose up -d --build --wait
```

El primer arranque construye las imágenes, instala las gems y los paquetes de pnpm y prepara la base de datos; no hay pasos manuales. Los siguientes arranques reutilizan los volúmenes y tardan segundos. `make up` espera a que todos los servicios estén `healthy`/`running`.

Para comprobar el entorno de punta a punta:

```sh
make smoke                       # health, ready, panel, booking, Mailpit y websockets de HMR
./infra/scripts/hmr-check.sh     # edita un componente y espera el update de HMR a través del proxy
```

## URLs

Todo se sirve desde **un solo origen**, `http://localhost:8080` ([ADR-0013](docs/adr/0013-monorepo-y-mismo-origen.md)): sin CORS y con las cookies y el CSRF comportándose igual que en producción.

| Qué | URL |
| --- | --- |
| Panel (staff) | <http://localhost:8080/> |
| Reserva pública (booking) | <http://localhost:8080/c/demo> |
| API | <http://localhost:8080/api/...> |
| Liveness (sin tocar la BD) | <http://localhost:8080/api/health> |
| Readiness (PostgreSQL + Redis) | <http://localhost:8080/api/ready> |
| Mailpit (correos de desarrollo) | <http://localhost:8025> |

Servicios de `compose.yaml`: `db` (PostgreSQL 18), `redis`, `api` (Rails), `worker` (Sidekiq), `panel` y `booking` (Vite), `mailpit` y `proxy` (Caddy). Solo `proxy` (8080) y `mailpit` (8025) publican puertos en el host.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `make up` / `make down` | Levanta / detiene el entorno (`down` conserva los datos) |
| `make logs` (`s=api`) | Sigue los logs, de todos los servicios o de uno |
| `make sh-api` | Shell dentro del contenedor de la API |
| `make console` | Consola de Rails |
| `make reset-db` | Recrea la base de datos desde cero (destructivo) |
| `make test` | Suite completa: backend (RSpec) y frontend (Vitest) |
| `make ci` | Los mismos pasos que CI, en Docker (`bin/ci`; `make ci s=backend-test` para una etapa) |
| `make smoke` | Verificación de humo a través del proxy |

Cualquier otro comando se ejecuta dentro del contenedor, por ejemplo `docker compose exec api bin/rails db:migrate` o `docker compose exec panel pnpm add <paquete>`.


## Estructura

```
backend/     Rails 8 en modo API (rutas bajo /api)
frontend/    workspace pnpm: apps/panel, apps/booking, packages/config (ESLint, Prettier, tsconfig)
infra/       docker/ (Dockerfiles de desarrollo), proxy/ (Caddy), scripts/ (verificación), github/ (protección de rama)
.github/     workflows de CI, Dependabot y plantilla de PR
bin/ci       los mismos pasos que CI, dentro de Docker
docs/        documentación: fuente única de verdad
compose.yaml entorno de desarrollo
```

## Configuración

Los valores por defecto de `compose.yaml` funcionan sin configurar nada. Para cambiar puertos o credenciales de desarrollo, define las variables (`PROXY_PORT`, `MAILPIT_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `REDIS_URL`) en un archivo `.env` en la raíz (ignorado por git), partiendo de [`.env.example`](.env.example): `cp .env.example .env`. Los valores por defecto son solo de desarrollo; nunca se versionan secretos reales.

`make up` pasa tu UID/GID a los Dockerfiles: los contenedores no corren como root y los archivos que crean (gems, `pnpm-lock.yaml`, migraciones) pertenecen a tu usuario. Si usas `docker compose up` directamente en Linux con un UID distinto de 1000, exporta antes `HOST_UID=$(id -u) HOST_GID=$(id -g)`.

## Solución de problemas

| Síntoma | Causa y solución |
| --- | --- |
| `port is already allocated` (8080 u 8025) | Otro proceso usa el puerto. Cambia `PROXY_PORT` / `MAILPIT_PORT` en `.env` (y abre esa URL) |
| `make up` tarda mucho la primera vez | Es normal (imágenes, gems, paquetes). Los volúmenes con nombre hacen que las siguientes veces sean rápidas |
| La API no queda `healthy` | `make logs s=api`. Suele ser un error en una migración o en una gem recién añadida |
| Cambié el `Gemfile` o `package.json` | `docker compose exec api bundle install` / `docker compose exec panel pnpm install` (o reinicia el servicio: el arranque instala lo que falte) |
| Archivos con dueño `root` | Se construyó la imagen sin tu UID: `make down && make up` (reconstruye con `HOST_UID`/`HOST_GID`) |
| El HMR no refresca el navegador | Verifica que entras por `http://localhost:8080` (no por 5173/5174) y corre `./infra/scripts/hmr-check.sh` |
| Quiero empezar de cero | `docker compose down -v` borra también los volúmenes (base de datos, gems, `node_modules`) |
| El worker no arranca | Espera a que `api` esté `healthy` (instala las gems); `make logs s=worker` |
