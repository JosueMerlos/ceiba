# Atajos de desarrollo. Todo corre en Docker: el host solo necesita Docker y Git.
# HOST_UID/HOST_GID se pasan a los Dockerfiles para que los archivos creados desde un
# contenedor pertenezcan al usuario del host y no a root.
export HOST_UID ?= $(shell id -u)
export HOST_GID ?= $(shell id -g)

COMPOSE ?= docker compose

.DEFAULT_GOAL := help
.PHONY: help up down logs ps sh-api console db-roles reset-db test smoke hmr-check ci

help: ## Lista los atajos
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-10s %s\n", $$1, $$2}'

up: ## Construye y levanta todo el entorno (espera a que todo esté healthy)
	$(COMPOSE) up -d --build --wait

down: ## Detiene el entorno (conserva los volúmenes y los datos)
	$(COMPOSE) down

logs: ## Sigue los logs (make logs s=api para un solo servicio)
	$(COMPOSE) logs -f --tail=100 $(s)

ps: ## Estado de los servicios
	$(COMPOSE) ps

sh-api: ## Shell dentro del contenedor de la API
	$(COMPOSE) exec api bash

console: ## Consola de Rails
	$(COMPOSE) exec api bin/rails console

db-roles: ## Aplica (idempotente) los roles app_owner/app_user a un volumen de BD que ya existía
	$(COMPOSE) up -d --wait db
	$(COMPOSE) exec -T db /docker-entrypoint-initdb.d/10-roles.sh

reset-db: ## Recrea la base de datos de desarrollo y de test desde cero (DESTRUCTIVO)
	$(COMPOSE) exec api bin/rails db:drop db:create db:migrate

test: ## Corre toda la suite (backend + frontend)
	$(COMPOSE) exec -e RAILS_ENV=test api bundle exec rspec
	$(COMPOSE) exec -w /app/frontend panel pnpm -r test

smoke: ## Verifica el entorno de punta a punta a través del proxy
	./infra/scripts/smoke.sh

hmr-check: ## Edita un componente y verifica el HMR a través del proxy (panel y booking)
	./infra/scripts/hmr-check.sh

ci: ## Corre en Docker los mismos pasos que CI (make ci s="backend-test" para una etapa)
	./bin/ci $(s)
