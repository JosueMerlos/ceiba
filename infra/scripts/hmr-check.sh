#!/usr/bin/env bash
# Verifica el HMR de panel y booking a través del proxy. El cliente websocket corre dentro de
# la red de Compose (contenedor panel, que ya tiene Node) y entra por proxy:8080, como un navegador.
set -euo pipefail
cd "$(dirname "$0")/../.."
script=infra/scripts/hmr-check.mjs
docker compose exec -T panel node --input-type=module - panel / <"$script"
docker compose exec -T panel node --input-type=module - booking /c/ <"$script"
