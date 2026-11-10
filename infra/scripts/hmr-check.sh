#!/usr/bin/env bash
# Checks HMR for panel and booking through the proxy. The websocket client runs inside the Compose network (panel
# container, which already has Node) and connects via proxy:8080, like a browser.
set -euo pipefail
cd "$(dirname "$0")/../.."
script=infra/scripts/hmr-check.mjs
docker compose exec -T panel node --input-type=module - panel / <"$script"
docker compose exec -T panel node --input-type=module - booking /c/ <"$script"
