# 12 — Estrategia de testing

> Aplica a todos los hitos. Modo de trabajo: **TDD estricto**: cada criterio de aceptación nace como un test que falla.

## Pirámide

| Nivel | Herramienta | Qué cubre | Volumen |
| --- | --- | --- | --- |
| Unitario de dominio | RSpec (POROs) | Motor de disponibilidad, máquina de estados, resolución de settings, permisos | Mucho |
| Modelo / BD | RSpec + PostgreSQL real | Validaciones, **restricciones** (exclusion, FKs compuestas, CHECK), RLS | Medio |
| Request / contrato | RSpec request specs + rswag | Endpoints, status, problem+json, autorización, contrato OpenAPI | Medio |
| Jobs y eventos | RSpec + `Sidekiq::Testing` | Relay, idempotencia de consumidores, propagación del tenant | Medio |
| Frontend unitario | Vitest + Testing Library + MSW | Componentes presentacionales, hooks, gates, formularios | Medio |
| E2E | Playwright | 5–8 flujos críticos completos | Poco |

**Nunca se mockea PostgreSQL**: las garantías viven en la BD y se prueban contra la BD real.

## Suites de plataforma obligatorias (harness reutilizables)

Son las que hacen que la extensibilidad sea **segura**: cubren automáticamente a los modelos y endpoints nuevos.

### 1. Aislamiento de tenant (M0.05)

- Descubre todos los modelos con columna `organization_id`.
- Para cada uno: sin tenant → error; con tenant A → no ve registros de B; `find` de un id de B dentro de A → `RecordNotFound`.
- Si a un modelo le falta su factory, el test **falla** (no se salta el modelo).

### 2. Bypass de RLS (M4.03)

- Con `acts_as_tenant` desactivado a propósito y `SET LOCAL app.organization_id = A`, una consulta SQL cruda sobre cada tabla tenant devuelve **solo** filas de A.
- Sin `app.organization_id` definido, devuelve **cero** filas.

### 3. Matriz de autorización (M0.08)

- Tabla de casos: **rol × alcance × recurso × acción → permitido/denegado**, generada desde la matriz de [04](04-access-control.md).
- Cubre explícitamente los casos de "misma organización, otra empresa" y "misma empresa, otra sucursal".
- Un permiso usado en una policy y no declarado en ningún manifiesto → falla.
- Toda acción de controlador sin `authorize` / `policy_scope` → falla (`verify_authorized`).

### 4. Cobertura de módulos (M0.09)

- Todos los manifiestos son válidos.
- Todo endpoint de un pack de módulo devuelve `404` si el módulo está inactivo en la empresa (se recorren las rutas del pack automáticamente).

### 5. Contrato (M0.06)

- Todo endpoint bajo `/api` tiene un spec de rswag.
- El OpenAPI generado coincide con el commiteado; el cliente TS generado coincide con el commiteado.

### 6. Eventos (M0.10)

- Todo evento publicado valida contra su esquema.
- Todo consumidor ejecutado dos veces con el mismo evento produce un solo efecto.

## Dominio de citas: pruebas específicas

- **Property-based** (gema `rantly` o generadores propios) sobre el motor de disponibilidad. Invariantes:
  - ningún hueco devuelto se solapa con una cita existente del profesional **ni** del recurso;
  - todo hueco cae dentro del horario de la sucursal y del profesional, fuera de sus ausencias;
  - todo hueco respeta la anticipación mínima y máxima;
  - la duración del hueco = suma de los servicios + buffers.
- **DST**: los mismos escenarios con `America/New_York` o `America/Mexico_City` históricas, aunque Nicaragua no use horario de verano.
- **Concurrencia** (tests con hilos y conexiones separadas):
  - N reservas simultáneas del mismo hueco → exactamente 1 éxito y N-1 `409`;
  - dos reprogramaciones simultáneas de la misma cita → 1 cita nueva y un `409`.

## Seguridad

- Spec por regla de Rack::Attack (`freeze_time`, store reiniciado entre ejemplos).
- Test del falso positivo de NAT: 6 usuarios distintos tras una misma IP no se bloquean.
- Specs de CSRF: una mutación sin token o con `Origin` ajeno → `403` (`packs/platform/identity/spec/requests/csrf_spec.rb`).
- Specs de cookies: flags presentes; sesión revocada → `401` (`auth_spec.rb`; `Secure`/`__Host-` con `config.x.auth.secure_cookies` activado y `https!`).
- **Deny by default:** `spec/requests/api/authentication_spec.rb` recorre todas las rutas del router sin sesión y exige `401` salvo una allowlist comentada y sin entradas obsoletas.
- **Login en specs de request:** `sign_in(user)` (`spec/support/authentication_helpers.rb`) hace el login real por HTTP y devuelve el token CSRF (`csrf_headers`); `browser: open_session` simula otro navegador con su propio jar de cookies. Las sesiones se prueban con `travel`/`travel_back` (12 h de inactividad, 7 días absolutos).

## E2E críticos (Playwright)

1. Login → selector de contexto → agenda vacía.
2. Staff crea una cita, la mueve y la cancela.
3. Cliente reserva en `/c/:slug` desde un viewport móvil.
4. Cliente cancela desde el enlace firmado.
5. Módulo desactivado → desaparece del menú y la URL directa da "no encontrado".
6. Usuario con dos organizaciones cambia de contexto y no ve datos de la otra.

## Factories

- Las factories derivan `organization_id` del padre (`company.organization_id`) y **nunca** lo generan por separado, para no violar las FKs compuestas.
- Helper `with_tenant(org) { ... }` en specs; un spec que toca modelos tenant sin contexto falla por diseño.
- Traits de forma de organización: `:single_business` (1·1·1) y `:franchise` (1·2·3).

## Calidad

- Sin umbral de cobertura global como objetivo. Sí es obligatorio: las seis suites de plataforma y los property tests del motor.
- Tiempo de la suite backend: objetivo menor a 3 min en CI. Si crece, paralelizar (`parallel_tests` o `turbo_tests`) antes de recortar tests.

## Herramientas de calidad y CI (M0.02)

| Capa | Herramienta | Notas |
| --- | --- | --- |
| Backend tests | RSpec 8 + FactoryBot, `spec/` (`requests/`, `services/`, `config/`, `support/`) | Sustituye a minitest. `bin/ci-test` corre con `CI=true` (eager load activo) |
| Backend lint | RuboCop con `rubocop-rails-omakase` como base + `rubocop-rails`, `rubocop-rspec`, `rubocop-factory_bot` | **Decisión:** omakase fija el estilo de Rails 8 (el que ya tiene el código generado: comillas dobles, espacios en `[ ]`) y evita discutir formato; las reglas de Rails y RSpec se añaden encima porque omakase no las trae. Los contextos de los specs se escriben en español (`con`, `sin`, `cuando`, `al`, `si`) |
| Seguridad backend | `brakeman`, `bundler-audit` | Ignorados solo en `backend/.bundler-audit.yml`, con `# revisar: AAAA-MM-DD \| motivo: ...`; un spec (`spec/config/audit_ignores_spec.rb`) exige motivo y falla si la fecha venció |
| Frontend | ESLint 10 (flat config), Prettier, `tsc --noEmit` (TypeScript estricto), Vitest, `pnpm audit --audit-level=high` | Config compartida en `frontend/packages/config` (`@ceiba/config`), con tests propios |
| Contrato API (M0.06) | Specs de rswag (`spec/api`, `packs/*/spec/api`), Vitest + MSW en `packages/api-client`, `tsc` sobre fixtures de campo inexistente, `infra/scripts/check-api-contract_test.sh` | Detalle en [07](07-api-contract.md) |
| Pasos de CI | `backend/bin/ci-{lint,test,security,openapi}` y `frontend/bin/ci-{lint,test,security,api-client}` | Los llaman tanto el workflow como `bin/ci`: una sola definición de cada paso |

**Pruebas de resiliencia en `/api/ready`:** además de dependencia caída o que acepta la conexión y nunca responde (servidor TCP "agujero negro", `spec/support/blackhole_server.rb`), hay un caso de PostgreSQL que conecta bien pero cuyo `SELECT 1` se cuelga (se afirma 503 en menos de 3 s y que se cerró la conexión efímera) y una verificación de que el pool de Active Record no se toca (`spec/support/connection_pool_spy.rb` espía `checkout`, `with_connection` y `lease_connection`; con fixtures transaccionales solo vigilar `checkout` no detectaría nada).

