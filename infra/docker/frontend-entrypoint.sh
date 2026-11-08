#!/bin/sh
# Arranque de panel y booking. Idempotente: con node_modules al día, pnpm no descarga nada.
set -e

pnpm install --frozen-lockfile --prefer-offline

exec "$@"
