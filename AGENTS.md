# Guía para agentes de IA (Claude Code, OpenCode)

Ceiba combina dos flujos con responsabilidades separadas: el **SDD de gentle-ai** para diseñar lo que aún no está decidido
y **ticket-harness** para ejecutar lo que ya está decidido (hito → plan → implementación → QA de UI → commit → PR →
seguimiento). Ver [Qué flujo usar](#qué-flujo-usar). El humano aprueba cada decisión que importa. Claude Code y OpenCode
leen este archivo de forma nativa.

## Qué flujo usar

La elección del flujo la hace esta tabla, no el agente. Si el trabajo no encaja claramente en una fila, PREGUNTA al
desarrollador antes de empezar; nunca mezcles los dos flujos en un mismo cambio.

| Situación | Flujo | Resultado |
| --- | --- | --- |
| Hito que ya existe en `docs/milestones/` (tiene criterios de aceptación) | ticket-harness: `ticket-plan` → `apply-plan` → `ui-qa` → `commit` → `watch-pr` | Código y tests. El hito ES la spec |
| Trabajo sin decidir: módulo nuevo, elección tecnológica, cambio de arquitectura, hito pendiente de diseño | SDD de gentle-ai: `sdd-explore` → `sdd-propose` → `sdd-design` (y `sdd-spec` si hace falta) | Un ADR (`docs/templates/adr.md`) y uno o más hitos (`docs/templates/milestone.md`) en `docs/` |
| Bug suelto o deuda técnica | ticket-harness: `bug-bash` | Código y tests |
| Memoria entre sesiones | engram, en cualquier flujo | engram |

Reglas del SDD en ceiba:

- **El SDD termina en `docs/`.** Sus artefactos (en engram, el almacén por defecto) son borradores de trabajo; el cambio no
  está diseñado hasta que existen el ADR y el hito en `docs/`, revisados por el desarrollador. Nunca dejes una decisión
  viviendo solo en engram ni en `openspec/` (no se usa en ceiba): `docs/` es la fuente única de verdad.
- **La ejecución siempre es con ticket-harness.** Una vez escrito el hito, se implementa con `ticket-plan` y `apply-plan`.
  En ceiba NO se usan `sdd-apply`, `sdd-verify`, `sdd-archive` ni `branch-pr` (este último exige issues de GitHub aprobados,
  y ceiba trabaja por hitos).
- Si una instrucción global del orquestador SDD contradice esta sección, gana esta sección.

- **Fuente única de verdad:** [`docs/`](docs/README.md). Ante una duda de arquitectura, lee el documento de `docs/architecture/`
  o el ADR correspondiente antes de decidir; lo que no está en `docs/` no está decidido.
- **Configuración del harness:** [`harness.config.md`](harness.config.md) (comandos, formato de commit, ramas, planes).
  Las skills la leen; no repitas esos valores en otro sitio.
- **Skills:** instaladas a nivel de usuario (`~/.claude/skills`, que OpenCode también lee): `ticket-plan`, `apply-plan`,
  `auto-ticket`, `bug-bash`, `ui-qa`, `commit`, `watch-pr`, `reload-test-db`.

## Reglas del proyecto (léelas antes de planificar o editar)

Adaptadas del harness a ceiba. Si una regla del harness o de una skill contradice estas, **ganan estas**.

- [`docs/harness/seguridad.md`](docs/harness/seguridad.md): entornos, secretos, tiempo, tenancy, dinero, API, migraciones
- [`docs/harness/testing.md`](docs/harness/testing.md): TDD estricto, aserciones fuertes, mocks, fixtures
- [`docs/harness/verificacion.md`](docs/harness/verificacion.md): qué correr, evidencia, criterios de aceptación
- [`docs/harness/calidad-de-codigo.md`](docs/harness/calidad-de-codigo.md): alcance, barrido de llamadas, comentarios
- [`docs/harness/rails.md`](docs/harness/rails.md): RSpec, RuboCop, migraciones y Packwerk en ceiba

Reglas de git y PR que no se copiaron (las skills `commit` y `watch-pr` las traen):
`~/projects/ticket-harness/core/rules/git-and-pr.md`, con los overrides de abajo.

## Compuertas

1. **Git.** Merge a `main`, force-push, despliegue y borrado de ramas remotas: nunca sin aprobación explícita del
   desarrollador, cada vez. Cuando el desarrollador lanza un hito o un bug en la sesión, quedan autorizados para ese trabajo,
   sin pedir OK ni mostrar el diff, el commit, el push de su propia rama (`feat/m<fase>.<nn>-*`, `fix/*`) y abrir su PR:
   la revisión del código la hace el desarrollador en el PR. Si se retoma en otra sesión, el desarrollador lo vuelve a lanzar.
   Anula la confirmación previa al commit de las skills `commit` y `watch-pr` y de `git-and-pr.md`.
2. Primero el plan, revisado. Las decisiones abiertas las resuelve el desarrollador; las delegables (ver
   [Autonomía de los agentes](#autonomía-de-los-agentes)) las resuelve el agente siguiendo la convención y las reporta.
3. Un cambio de comportamiento empieza con un test que corriste y viste fallar (TDD estricto, ver
   [`12-testing-strategy`](docs/architecture/12-testing-strategy.md)).
4. Evidencia antes de afirmar: reporta los comandos exactos y su resultado.
5. Nunca leer, imprimir ni versionar secretos (`.env`, `backend/config/*.key`).

## Autonomía de los agentes

El objetivo es que un hito avance sin detenerse salvo en lo que de verdad es del desarrollador.

- **Decisiones delegables:** el agente las toma siguiendo la convención documentada y las registra en el plan en una sección
  "Decisiones delegadas (convención)", con el encabezado `**N. <decisión>** - Resuelta: <opción> (delegada), <fecha>`
  (el token `Resuelta:` es el que la compuerta de `apply-plan` reconoce como decisión resuelta). Se listan también en el
  resumen del PR. Son delegables:
  - detalles de contrato de endpoints **nuevos y sin publicar**: nombres de parámetros, códigos de error según
    [`07-api-contract`](docs/architecture/07-api-contract.md), semántica de `PUT`/`PATCH`, forma de la respuesta;
  - validaciones y límites razonables (longitudes, rangos, tipos);
  - datos demo de los seeds, sin alterar los fixtures en los que se apoyan los E2E;
  - todo lo que ya fija un ADR o un patrón existente (por ejemplo, el de [ADR-0033](docs/adr/0033-autorizacion-y-pii-de-clientes-y-servicios.md)).
- **Siempre del desarrollador:** cambios al modelo de autorización (motor, alcance o matriz de
  [`04-access-control`](docs/architecture/04-access-control.md)), PII y privacidad, dinero, esquema de tablas existentes,
  borrado o reescritura de datos, contratos ya publicados, nuevas dependencias no previstas por el hito y cualquier
  desviación del alcance. Ante la duda entre delegable y no, pregunta.
- **Premisas:** una afirmación de que algo **no existe** (un helper, un manejador, un índice) se verifica con una búsqueda
  antes de usarla para decidir.
- **Segunda opinión:** en Claude Code, todos los agentes (orquestador, implementadores, revisores) tienen la herramienta
  `advisor` (configurada con Fable). Consúltala antes de una decisión no obvia o tras dos intentos fallidos. Para una revisión
  independiente, el orquestador lanza un agente de solo lectura con el modelo `fable`. Un implementador con dudas sobre una
  decisión no delegable la devuelve en su reporte en vez de adivinar.
- **Revisión antes del merge**, sin pedir permiso para lanzarla: primero `thermo-nuclear-code-quality-review` (estructura),
  después `adversarial-reviewer` (cambios de rutina) o `judgment-day` (tenancy, base de datos, autorización, PII, dinero).
  En `judgment-day`, los hallazgos CRITICAL y WARNING reales confirmados por ambos jueces se corrigen sin preguntar; solo
  las sospechas, las contradicciones y las decisiones de producto vuelven al desarrollador.
- **Verificación por fase y entorno:** ver [`verificacion.md`](docs/harness/verificacion.md) (suites que cada fase debe
  correr, reinicio del entorno, un solo dueño de la base de test).

## Overrides de ceiba sobre el harness

- **Idioma:** planes, documentación, contextos de RSpec (`con`, `sin`, `cuando`) y asunto de commits/PR en **español**.
  Identificadores y **comentarios de código en inglés** (regla del harness).
- **Referencias en comentarios:** prohibido citar hitos, ADRs, fases ni rutas de `docs/` (`M0.11`, `ADR-0013`, `F0`) en
  comentarios de código. El comentario explica el porqué por sí solo; la trazabilidad vive en `docs/` y en el historial de
  git.
- **Commits y títulos de PR:** conventional commits, `tipo(ámbito): asunto` (tipos: feat, fix, docs, style, refactor, perf,
  test, build, ci, chore, revert). Lo valida `infra/scripts/check-pr-title.sh`. Sin `Co-Authored-By` ni atribución a IA.
  Patrón TDD en la rama: un commit `test(...)` con el rojo (`(rojo: ...)`) y luego el `feat`/`fix` que lo pone en verde.
  El PR se integra con *squash*: en `main` queda un commit con el título del PR y el rojo queda como evidencia en el PR.
- **"Ticket" = hito.** Las claves son `M<fase>.<nn>` (p. ej. `M0.14`) y el ticket es el archivo
  `docs/milestones/<fase>/M<fase>.<nn>-*.md`: léelo directamente (no hay Jira/Linear). Los bugs sueltos van sin clave.
- **Ramas:** `feat/m<fase>.<nn>-<slug>` en minúsculas (p. ej. `feat/m0.12-frontend-shell`), `fix/<slug>` para arreglos sin
  hito. Base: `main`, protegida (ver `infra/github/branch-protection.sh`): solo cambia por PR con los checks de CI en verde.
- **Un PR por hito, directo a `main`.** Sin ramas de release ni merges locales a `main` (la protección exige historial
  lineal). Cada PR se asigna al Milestone de GitHub de su fase (p. ej. "F1"), y el cierre de una fase se marca con un tag
  anotado en `main` (`f1`). Mergear (`gh pr merge --squash`, también con `--auto`) sigue requiriendo aprobación explícita.
- **Cierre de un hito:** cuando está completo en local (criterios probados y `make ci` en verde), se marca `terminado`
  (✅ en [`docs/roadmap/README.md`](docs/roadmap/README.md) y en el archivo del hito) en el mismo PR, antes de mergear.
- **Todo corre en Docker.** El host no tiene Ruby ni Node: los comandos van por `docker compose exec` o `make` (ver
  [`README.md`](README.md#comandos)). Rutas de RSpec relativas a `backend/`.
- **Test de un archivo:** `docker compose exec -e RAILS_ENV=test api bundle exec rspec <ruta>`;
  frontend: `docker compose exec -w /app/frontend panel pnpm -r test`.
- **Lint:** `docker compose exec api bundle exec rubocop <archivos>`; frontend:
  `docker compose exec -w /app/frontend panel pnpm lint` (ESLint), `pnpm format:check` y `pnpm typecheck` (mismo prefijo).
- **Verificación completa antes de un push:** `make ci` (= `bin/ci`, los mismos pasos que CI); una etapa con
  `make ci s=<etapa>`. Si tocaste endpoints o serializers: `bin/api-generate`. Si tocaste UI: `make e2e` y `make smoke`.
- **Base de test desfasada** ("migraciones pendientes"): `make migrate` y, si persiste, `make db-prepare`. NO uses
  `reload-test-db` aquí: ceiba usa `structure.sql` con roles `app_owner`/`app_user` (ver
  [`09-data-conventions`](docs/architecture/09-data-conventions.md#roles-de-base-de-datos)).
- **Arquitectura:** monolito modular con Packwerk (`backend/packs/platform/*`, `backend/packs/modules/*`), tenancy de tres
  barreras (acts_as_tenant, FKs compuestas, RLS), UUIDv7, contrato OpenAPI con cliente TS generado. Ver
  [`02`](docs/architecture/02-modular-monolith.md), [`03`](docs/architecture/03-multi-tenancy.md),
  [`07`](docs/architecture/07-api-contract.md).
- **Plantilla de PR:** [`.github/pull_request_template.md`](.github/pull_request_template.md).
- **Una decisión nueva o cambiada** se documenta en `docs/` (ADR con [`docs/templates/adr.md`](docs/templates/adr.md))
  en el mismo cambio.
