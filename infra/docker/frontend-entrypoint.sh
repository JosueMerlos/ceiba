#!/bin/sh
# Startup for panel and booking. Idempotent: with node_modules up to date, pnpm downloads nothing.
set -e

pnpm install --frozen-lockfile --prefer-offline

exec "$@"
