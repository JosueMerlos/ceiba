#!/bin/sh
# Startup for api and worker. Idempotent: reinstalls nothing when everything is up to date.
set -e

# Install gems only when missing (they live in a named volume).
bundle check >/dev/null 2>&1 || bundle install

if [ "${RUN_SETUP:-false}" = "true" ]; then
  rm -f tmp/pids/server.pid
  bin/setup --skip-server
fi

exec "$@"
