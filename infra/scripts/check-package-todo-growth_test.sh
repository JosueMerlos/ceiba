#!/usr/bin/env bash
# Tests for check-package-todo-growth.sh on temporary git repositories.
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/check-package-todo-growth.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
new_repo() { # creates a repo whose main already has 2 lines of debt
  rm -rf "$work/repo" && mkdir -p "$work/repo/packs/modules/foo" && cd "$work/repo" || exit 1
  git init -q -b main && git config user.email t@t && git config user.name t
  printf '"packs/platform/bar":\n  "::Bar::Thing":\n' > packs/modules/foo/package_todo.yml
  git add -A && git commit -q -m "chore: base"
}
expect() { # expect <ok|fail> <description> [script args]
  local expected=$1 description=$2; shift 2
  local actual=ok
  "$script" "$@" >/dev/null 2>&1 || actual=fail
  if [ "$actual" = "$expected" ]; then echo "ok    [$expected] $description"
  else echo "FALLA [$expected esperado, fue $actual] $description"; failures=$((failures + 1)); fi
}

new_repo
expect ok "sin cambios (rama == main)"

git checkout -q -b feat/grow
printf '  "::Bar::Other":\n' >> packs/modules/foo/package_todo.yml
git commit -qam "feat: grow"
expect fail "commit que agrega líneas a un package_todo.yml"

new_repo; git checkout -q -b feat/shrink
printf '"packs/platform/bar":\n' > packs/modules/foo/package_todo.yml
git commit -qam "fix: shrink"
expect ok "commit que solo quita líneas"

new_repo; git checkout -q -b feat/new
mkdir -p packs/modules/baz && printf '"packs/platform/bar":\n  "::Bar::X":\n' > packs/modules/baz/package_todo.yml
git add -A && git commit -qm "feat: new todo"
expect fail "package_todo.yml nuevo con contenido"

new_repo; git checkout -q -b feat/untracked
mkdir -p packs/modules/baz && printf '"packs/platform/bar":\n' > packs/modules/baz/package_todo.yml
expect fail "package_todo.yml nuevo sin versionar"

new_repo; git checkout -q -b feat/dirty
printf '  "::Bar::Other":\n' >> packs/modules/foo/package_todo.yml
expect fail "cambio sin commitear que agrega líneas"

new_repo; git checkout -q -b feat/other
mkdir -p docs && echo x > docs/a.md && git add -A && git commit -qm "docs: a"
expect ok "cambios que no tocan package_todo.yml"

new_repo; git checkout -q -b feat/main-moved
git checkout -q main && printf '  "::Bar::More":\n' >> packs/modules/foo/package_todo.yml && git commit -qam "chore: main grew"
git checkout -q feat/main-moved
expect ok "la deuda que main agregó después de la rama no cuenta (merge-base)"
expect ok "base explícita por argumento" main
BASE_REF=main expect ok "base por BASE_REF"
expect fail "base inexistente" no-existe

zeros=0000000000000000000000000000000000000000
new_repo
printf '  "::Bar::Other":\n' >> packs/modules/foo/package_todo.yml; git commit -qam "feat: grow"
BASE_REF=$zeros expect fail "primer push (SHA previo 000...): compara con HEAD~1 y detecta el crecimiento"
git commit -q --allow-empty -m "chore: empty"
BASE_REF=$zeros expect ok "primer push (SHA previo 000...) sin crecimiento en el último commit"
rm -rf "$work/solo" && mkdir "$work/solo" && cd "$work/solo" && git init -q -b main && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m "chore: root"
BASE_REF=$zeros expect ok "primer push con un solo commit (sin HEAD~1): se omite con aviso"

echo
[ "$failures" -eq 0 ] && echo "todas las pruebas pasaron" || echo "$failures prueba(s) fallaron"
exit "$failures"
