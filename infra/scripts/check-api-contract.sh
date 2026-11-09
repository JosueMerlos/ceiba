#!/usr/bin/env bash
# Drift del contrato API (M0.06, ADR-0012): regenera backend/openapi/v1.yaml desde los specs de rswag y el cliente
# TypeScript desde ese contrato, y falla si alguno difiere de lo versionado. Atrapa dos descuidos:
#   - cambiar un serializer/endpoint (y su spec) sin regenerar el contrato;
#   - cambiar el contrato sin regenerar el cliente.
#
# Los comandos de generación los pone quien llama (CI corre nativo; bin/ci los envuelve en Docker):
#   OPENAPI_GENERATE='cd backend && bin/rails openapi:generate' CLIENT_GENERATE='cd frontend && pnpm api:generate' \
#     infra/scripts/check-api-contract.sh
#
# Compara contra una copia hecha ANTES de regenerar (no contra el índice de git), así funciona igual con cambios sin
# commitear. Si hay drift, los archivos regenerados QUEDAN en el árbol de trabajo: revísalos y commitéalos.
set -uo pipefail

root="${ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
: "${OPENAPI_GENERATE:?define OPENAPI_GENERATE (comando que regenera backend/openapi/v1.yaml)}"
: "${CLIENT_GENERATE:?define CLIENT_GENERATE (comando que regenera frontend/packages/api-client/src/schema.d.ts)}"

contract="$root/backend/openapi/v1.yaml"
client="$root/frontend/packages/api-client/src/schema.d.ts"
snapshot=$(mktemp -d)
trap 'rm -rf "$snapshot"' EXIT

for file in "$contract" "$client"; do
  [ -f "$file" ] || { echo "check-api-contract: no existe ${file#"$root"/} (genéralo y versiónalo)" >&2; exit 1; }
done
cp "$contract" "$snapshot/contract"
cp "$client" "$snapshot/client"

run() { # run <descripción> <comando>
  echo "== $1 =="
  (cd "$root" && bash -c "$2") || { echo "check-api-contract: falló la generación de $1" >&2; exit 1; }
}
run "contrato (rswag)" "$OPENAPI_GENERATE"
run "cliente (openapi-typescript)" "$CLIENT_GENERATE"

drift=0
if ! diff -u "$snapshot/contract" "$contract"; then
  echo "check-api-contract: el contrato backend/openapi/v1.yaml está desactualizado respecto de los specs de rswag." >&2
  drift=1
fi
if ! diff -u "$snapshot/client" "$client"; then
  echo "check-api-contract: el cliente frontend/packages/api-client/src/schema.d.ts está desactualizado respecto del contrato." >&2
  drift=1
fi
if [ "$drift" -ne 0 ]; then
  echo "check-api-contract: drift. Regenera con 'bin/api-generate' (o 'bin/rails openapi:generate' + 'pnpm api:generate') y versiona el resultado." >&2
  exit 1
fi
echo "check-api-contract: contrato y cliente al día"
