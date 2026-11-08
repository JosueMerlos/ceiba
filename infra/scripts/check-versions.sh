#!/usr/bin/env bash
# Verifica que las versiones de .tool-versions coincidan con los Dockerfiles, compose.yaml,
# .ruby-version, package.json y el workflow de CI (M0.02: "mismas versiones que .tool-versions").
# Uso: check-versions.sh [raíz-del-repo]
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root"

failures=0
version_of() { awk -v tool="$1" '$1 == tool { print $2 }' .tool-versions; }
expect_in() { # expect_in <archivo> <patrón fijo esperado> <descripción>
  if grep -qF -- "$2" "$1"; then echo "ok    $3"
  else echo "FALLA $3: se esperaba '$2' en $1" >&2; failures=$((failures + 1)); fi
}

ruby=$(version_of ruby); node=$(version_of nodejs); pnpm=$(version_of pnpm)
postgres=$(version_of postgres); redis=$(version_of redis)
for value in "$ruby" "$node" "$pnpm" "$postgres" "$redis"; do
  [ -n "$value" ] || { echo "FALLA .tool-versions incompleto" >&2; exit 1; }
done

expect_in infra/docker/api.Dockerfile       "FROM ruby:${ruby}-"          "Ruby ${ruby} en api.Dockerfile"
expect_in backend/.ruby-version             "ruby-${ruby}"                "Ruby ${ruby} en backend/.ruby-version"
expect_in infra/docker/frontend.Dockerfile  "FROM node:${node}-"          "Node ${node} en frontend.Dockerfile"
expect_in infra/docker/frontend.Dockerfile  "ARG PNPM_VERSION=${pnpm}"    "pnpm ${pnpm} en frontend.Dockerfile"
expect_in frontend/package.json             "\"packageManager\": \"pnpm@${pnpm}\"" "pnpm ${pnpm} en frontend/package.json"
expect_in frontend/package.json             "\"node\": \">=${node}\""     "Node ${node} en engines"
expect_in compose.yaml                      "image: postgres:${postgres}-" "PostgreSQL ${postgres} en compose.yaml"
expect_in compose.yaml                      "image: redis:${redis}-"       "Redis ${redis} en compose.yaml"
expect_in .github/workflows/ci.yml          "image: postgres:${postgres}-" "PostgreSQL ${postgres} en ci.yml"
expect_in .github/workflows/ci.yml          "image: redis:${redis}-"       "Redis ${redis} en ci.yml"
expect_in .github/workflows/ci.yml          "version: ${pnpm}"             "pnpm ${pnpm} en ci.yml"
expect_in .github/workflows/ci.yml          "node-version-file: .tool-versions" "Node desde .tool-versions en ci.yml"
expect_in .github/workflows/ci.yml          "rhysd/actionlint:1.7.12"      "Imagen de actionlint en ci.yml"
expect_in bin/ci                            "rhysd/actionlint:1.7.12"      "Imagen de actionlint en bin/ci"

[ "$failures" -eq 0 ] || { echo "$failures desajuste(s) de versiones" >&2; exit 1; }
echo "versiones consistentes"
