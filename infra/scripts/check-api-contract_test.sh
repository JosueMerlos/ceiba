#!/usr/bin/env bash
# Tests for check-api-contract.sh with fake generators on a temporary tree.
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/check-api-contract.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
new_tree() { # committed contract and client, both "up to date"
  rm -rf "$work/tree" && mkdir -p "$work/tree/backend/openapi" "$work/tree/frontend/packages/api-client/src"
  printf 'openapi: 3.0.3\npaths: {}\n' > "$work/tree/backend/openapi/v1.yaml"
  printf 'export interface paths {}\n' > "$work/tree/frontend/packages/api-client/src/schema.d.ts"
}
expect() { # expect <ok|fail> <description> <OpenAPI command> <client command> [expected output pattern]
  local expected=$1 description=$2 openapi_cmd=$3 client_cmd=$4 pattern=${5:-} output actual=ok
  output=$(ROOT="$work/tree" OPENAPI_GENERATE="$openapi_cmd" CLIENT_GENERATE="$client_cmd" "$script" 2>&1) || actual=fail
  if [ "$actual" != "$expected" ]; then echo "FALLA [$expected esperado, fue $actual] $description"; failures=$((failures + 1)); return; fi
  if [ -n "$pattern" ] && ! grep -qE "$pattern" <<<"$output"; then
    echo "FALLA [salida sin /$pattern/] $description"; failures=$((failures + 1)); return
  fi
  echo "ok    [$expected] $description"
}

openapi_file="$work/tree/backend/openapi/v1.yaml"
client_file="$work/tree/frontend/packages/api-client/src/schema.d.ts"

new_tree
expect ok "los generadores reproducen exactamente lo versionado" \
  "printf 'openapi: 3.0.3\npaths: {}\n' > '$openapi_file'" "printf 'export interface paths {}\n' > '$client_file'"

new_tree
expect fail "el contrato regenerado difiere del versionado (serializer cambiado sin regenerar)" \
  "printf 'openapi: 3.0.3\npaths: {x: 1}\n' > '$openapi_file'" "true" "contrato.*backend/openapi/v1.yaml"

new_tree
expect fail "el cliente regenerado difiere del versionado" \
  "true" "printf 'export interface paths { x: 1 }\n' > '$client_file'" "cliente.*schema.d.ts"

new_tree
expect fail "el cliente se regenera a partir del contrato regenerado (no del versionado)" \
  "printf 'openapi: 3.0.3\npaths: {y: 1}\n' > '$openapi_file'" "cp '$openapi_file' '$client_file'" "drift"

new_tree
expect fail "un generador que falla" "false" "true" "falló"

new_tree; rm "$openapi_file"
expect fail "falta el contrato versionado" "true" "true" "no existe"

new_tree
expect fail "faltan los comandos de generación" "" "" "OPENAPI_GENERATE"

[ "$failures" -eq 0 ] && echo "check-api-contract_test: ok" || { echo "$failures caso(s) fallaron" >&2; exit 1; }
