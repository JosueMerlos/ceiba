#!/bin/sh
# Arranque de api y worker. Idempotente: no reinstala nada si todo está al día.
set -e

# Instala gems solo si faltan (las gems viven en un volumen con nombre).
bundle check >/dev/null 2>&1 || bundle install

if [ "${RUN_SETUP:-false}" = "true" ]; then
  rm -f tmp/pids/server.pid
  bin/setup --skip-server
fi

exec "$@"
