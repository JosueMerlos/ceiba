#!/usr/bin/env bash
# Tests for e2e-evidence-group.sh: milestone branches group under M<fase>.<nn>, fix branches under their slug, and
# anything that is not a work branch (main, detached HEAD) does not group at all.
set -uo pipefail
cd "$(dirname "$0")"

failures=0
expect() { # expect <rama> <grupo esperado>
  local branch=$1 expected=$2 actual
  actual=$(./e2e-evidence-group.sh "$branch")
  if [ "$actual" = "$expected" ]; then
    echo "ok    [$branch] -> '${actual}'"
  else
    echo "FALLA [$branch] esperado '${expected}', fue '${actual}'"; failures=$((failures + 1))
  fi
}

# Hitos: la carpeta es el hito, sin el slug que lo describe.
expect "feat/m2.04-branding-por-empresa" "M2.04"
expect "feat/m2.02-agenda-del-staff"     "M2.02"
expect "feat/m10.3-algo"                 "M10.3"
expect "feat/M2.04-mayusculas"           "M2.04"

# Fixes sin hito: la carpeta es el slug completo de la rama.
expect "fix/error_500_endpoint_org" "error_500_endpoint_org"
expect "fix/picomatch-audit"        "picomatch-audit"

# Ramas que agrupan por su propio nombre, saneado para que sea un solo directorio.
expect "feat/algo/extra" "algo-extra"
expect "fix/../escape"   "escape"

# Sin hito ni fix: la evidencia queda en la raíz (sin subcarpeta).
expect "main"    ""
expect "HEAD"    ""
expect "release" ""

# Without an argument the script reads the current branch, so that path runs inside a throwaway repo on a known branch:
# running it against this checkout would make the result depend on where the suite runs (a feat/ worktree, main, CI).
script="$PWD/e2e-evidence-group.sh"
expect_current() { # expect_current <rama actual> <grupo esperado>
  local branch=$1 expected=$2 repo actual
  repo=$(mktemp -d)
  git -C "$repo" init -q -b "$branch"
  git -C "$repo" -c user.name=test -c user.email=test@example.invalid commit -q --allow-empty -m init
  actual=$(cd "$repo" && "$script")
  rm -rf "$repo"
  if [ "$actual" = "$expected" ]; then
    echo "ok    [sin argumento, rama $branch] -> '${actual}'"
  else
    echo "FALLA [sin argumento, rama $branch] esperado '${expected}', fue '${actual}'"; failures=$((failures + 1))
  fi
}

expect_current "feat/m2.03-clientes" "M2.03"
expect_current "main"                ""

[ "$failures" -eq 0 ] || { echo "$failures caso(s) fallaron"; exit 1; }
echo "todos los casos pasaron"
