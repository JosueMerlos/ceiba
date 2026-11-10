#!/usr/bin/env bash
# Checks that the versions in .tool-versions match the Dockerfiles, compose.yaml, .ruby-version, package.json and the CI
# workflow.
# Usage: check-versions.sh [repo-root]
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root"

failures=0
version_of() { awk -v tool="$1" '$1 == tool { print $2 }' .tool-versions; }
expect_in() { # expect_in <file> <expected fixed pattern> <description>
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

# The E2E image must match the @playwright/test version (the browsers ship in the image).
playwright=$(sed -n 's/.*"@playwright\/test": "\([0-9.]*\)".*/\1/p' frontend/e2e/package.json)
[ -n "$playwright" ] || { echo "FALLA no se encontró @playwright/test en frontend/e2e/package.json" >&2; exit 1; }
expect_in infra/docker/e2e.Dockerfile "FROM mcr.microsoft.com/playwright:v${playwright}-" "Playwright ${playwright} en e2e.Dockerfile"
expect_in infra/docker/e2e.Dockerfile "ARG PNPM_VERSION=${pnpm}" "pnpm ${pnpm} en e2e.Dockerfile"

# pg_dump (structure.sql) needs client and server on the SAME major version: the client installed in the api image and
# in the CI jobs with a database must match the postgres service's major version.
pg_major="${postgres%%.*}"
expect_in infra/docker/api.Dockerfile "postgresql-client-${pg_major}" "Cliente PostgreSQL ${pg_major} en api.Dockerfile"
[ "$(grep -cF -- "postgresql-client-${pg_major}" .github/workflows/ci.yml)" -ge 2 ] \
  && echo "ok    Cliente PostgreSQL ${pg_major} en los jobs de ci.yml con base de datos" \
  || { echo "FALLA se esperaba postgresql-client-${pg_major} en backend-migrations y backend-test de ci.yml" >&2; failures=$((failures + 1)); }

[ "$failures" -eq 0 ] || { echo "$failures desajuste(s) de versiones" >&2; exit 1; }
echo "versiones consistentes"
