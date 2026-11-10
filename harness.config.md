# Configuración de ticket-harness

Valores por proyecto que leen las skills y los scripts del harness. Las skills leen el bloque `yaml`; la prosa es para
humanos. Plantilla original y significado de cada clave: `~/projects/ticket-harness/templates/harness.config.md`.

Reglas de edición: una línea `clave: valor` plana por línea (los scripts la leen con `awk`). Un valor vacío significa "no
configurado": la skill lo resuelve desde `AGENTS.md` o se detiene y pregunta. Nunca inventa un comando.

```yaml
# --- Origen del ticket ------------------------------------------------------------
# No hay Jira/Linear: el "ticket" es un hito, archivo docs/milestones/<fase>/M<fase>.<nn>-*.md (ver AGENTS.md).
ticket_source: pasted
ticket_key_pattern: 'M[0-9]+\.[0-9]+'
ticket_url_prefix:

# --- Planes ---------------------------------------------------------------------------
# Planes de trabajo locales (gitignorados). Los planes originales del proyecto viven en el tag historico/plans.
plan_dir: .harness/plans
plan_language: Spanish

# --- Git ----------------------------------------------------------------------------------
# main está protegida: un PR por hito, integrado con squash (ver AGENTS.md).
base_branch: main
# Rama en minúsculas: feat/m0.14-<slug> (ver AGENTS.md); fix/<slug> sin hito.
branch_pattern: 'feat/{TICKET}-{slug}'
# Conventional commits con asunto en español (lo valida infra/scripts/check-pr-title.sh).
commit_title_format: '{type}({scope}): {title}'
# Vacío = ../ceiba-worktrees/<TICKET>
worktree_root:
# Archivos gitignorados que se copian (sin leerlos) a un worktree nuevo.
worktree_copy_files: .env

# --- Comandos de verificación (todo en Docker; rutas relativas a backend/) -------------
test_command: docker compose exec -e RAILS_ENV=test api bundle exec rspec {path}
lint_command: docker compose exec api bundle exec rubocop {files}
migrate_command: make migrate
# La base de test se repara con make migrate / make db-prepare (ver AGENTS.md); reload-test-db no aplica.
db_recovery: none

# --- Pull requests -----------------------------------------------------------------------
pr_template: .github/pull_request_template.md
watch_state_dir: .harness/pr-watch

# --- QA de UI -------------------------------------------------------------------------------
# E2E existentes: frontend/e2e (make e2e). Smokes del harness, si se crean, aquí:
ui_qa_dir: frontend/e2e/harness
```

## Política de auto-ticket

`auto-ticket` usa `.harness/auto-ticket-policy.yml` (local, gitignorado). Sin ese archivo se niega a correr.
