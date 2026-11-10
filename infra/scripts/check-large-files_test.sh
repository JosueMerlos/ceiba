#!/usr/bin/env bash
# Tests for check-large-files.sh on throwaway git repositories.
set -uo pipefail
script="$(cd "$(dirname "$0")" && pwd)/check-large-files.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0
new_repo() { # main with a small text file and an empty allowlist
  rm -rf "$work/repo" && mkdir -p "$work/repo/infra/scripts" && cd "$work/repo" || exit 1
  git init -q -b main && git config user.email t@t && git config user.name t
  echo "# allowlist" > infra/scripts/large-files-allowlist.txt
  echo "hola" > README.md
  printf 'ignored/\n' > .gitignore
  git add -A && git commit -q -m "chore: base"
}
binary() { mkdir -p "$(dirname "$1")" && head -c $(($2 * 1024)) /dev/urandom > "$1"; } # binary <path> <KiB>
text() { mkdir -p "$(dirname "$1")" && yes "linea de texto" | head -c $(($2 * 1024)) > "$1"; } # text <path> <KiB>
expect() { # expect <ok|fail> <description> [script args]
  local expected=$1 description=$2; shift 2
  local actual=ok
  "$script" "$@" >/dev/null 2>&1 || actual=fail
  if [ "$actual" = "$expected" ]; then echo "ok    [$expected] $description"
  else echo "FALLA [$expected esperado, fue $actual] $description"; failures=$((failures + 1)); fi
}

new_repo
expect ok "sin cambios (rama == main)"

new_repo; git checkout -q -b feat/small
binary assets/logo.png 99 && text docs/a.md 50 && git add -A && git commit -qm "feat: small"
expect ok "binario por debajo de 100 KiB y texto pequeño"

new_repo; git checkout -q -b feat/big-binary
binary frontend/e2e/screenshots/a.png 101 && git add -A && git commit -qm "feat: big binary"
expect fail "binario de más de 100 KiB commiteado"

new_repo; git checkout -q -b feat/big-text
text backend/db/huge.sql 1025 && git add -A && git commit -qm "feat: big text"
expect fail "archivo de texto de más de 1 MiB"

new_repo; git checkout -q -b feat/text-under-limit
text frontend/pnpm-lock.yaml 1000 && git add -A && git commit -qm "chore: lock"
expect ok "texto grande pero por debajo de 1 MiB"

new_repo; git checkout -q -b feat/added-then-removed
binary video.mp4 500 && git add -A && git commit -qm "feat: video"
git rm -q video.mp4 && git commit -qm "fix: remove video"
expect fail "binario agregado y borrado en la rama (queda en el historial)"

new_repo; git checkout -q -b feat/untracked
binary capture.png 200
expect fail "binario grande sin versionar (no ignorado)"

new_repo; git checkout -q -b feat/ignored
binary ignored/capture.png 200
expect ok "binario grande en una ruta gitignorada"

new_repo; git checkout -q -b feat/dirty
binary assets/logo.png 10 && git add -A && git commit -qm "feat: logo"
binary assets/logo.png 300
expect fail "archivo versionado que crece sin commitear"

new_repo; git checkout -q -b feat/allowed
printf 'assets/fonts/*.woff2 | fuente propia, no hay CDN permitido\n' >> infra/scripts/large-files-allowlist.txt
binary assets/fonts/inter.woff2 300 && git add -A && git commit -qm "feat: font"
expect ok "binario grande en una ruta permitida con motivo"

new_repo; git checkout -q -b feat/allowed-no-reason
printf 'assets/fonts/*.woff2\n' >> infra/scripts/large-files-allowlist.txt
binary assets/fonts/inter.woff2 300 && git add -A && git commit -qm "feat: font"
expect fail "entrada de la lista sin motivo"

new_repo
binary legacy.png 300 && git add -A && git commit -qm "chore: legacy on main"
git checkout -q -b feat/after-legacy && text docs/b.md 1 && git add -A && git commit -qm "docs: b"
expect ok "un binario que ya estaba en main no cuenta (merge-base)"
expect ok "base explícita por argumento" main
BASE_REF=main expect ok "base por BASE_REF"
expect fail "base inexistente" no-existe

zeros=0000000000000000000000000000000000000000
new_repo
binary big.png 300 && git add -A && git commit -qm "feat: big"
BASE_REF=$zeros expect fail "primer push (SHA previo 000...): compara con HEAD~1 y detecta el binario"
rm -rf "$work/solo" && mkdir "$work/solo" && cd "$work/solo" && git init -q -b main && git config user.email t@t && git config user.name t
git commit -q --allow-empty -m "chore: root"
BASE_REF=$zeros expect ok "primer push con un solo commit (sin HEAD~1): se omite con aviso"

echo
[ "$failures" -eq 0 ] && echo "todas las pruebas pasaron" || echo "$failures prueba(s) fallaron"
exit "$failures"
