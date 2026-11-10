#!/usr/bin/env bash
# Fails if the change ADDS lines to any package_todo.yml: violations are not "accepted for later". Debt may only shrink.
#
#   infra/scripts/check-package-todo-growth.sh [base]
#
# Compares the working tree (uncommitted changes included) with the merge-base between `base` and HEAD:
#   - in a CI PR:      base = origin/<target branch>  (CI passes BASE_REF)
#   - on a push to main: base = the SHA before the push (CI passes BASE_REF); if it is 000... (first push), HEAD~1
#   - locally: base = main (or origin/main if it exists and main does not)
# Needs enough history to compute the merge-base (in CI: fetch-depth: 0).
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

base_ref="${1:-${BASE_REF:-}}"
if [ -z "$base_ref" ]; then
  for candidate in main origin/main; do
    if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then base_ref=$candidate; break; fi
  done
fi
# First push of a branch (e.g. the first to main): GitHub reports the previous SHA as 40 zeros.
# Compare with HEAD's parent; with none (a single commit) there is nothing to compare against.
if [[ "$base_ref" =~ ^0+$ ]]; then
  if git rev-parse --verify --quiet "HEAD~1^{commit}" >/dev/null; then
    base_ref="HEAD~1"
  else
    echo "aviso: primer push sin commit previo; se omite la comparación de package_todo.yml" >&2
    exit 0
  fi
fi
if [ -z "$base_ref" ] || ! git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
  echo "check-package-todo-growth: no existe la referencia base '${base_ref:-main}' (¿falta fetch-depth: 0 o git fetch?)" >&2
  exit 2
fi

if ! base=$(git merge-base "$base_ref" HEAD 2>/dev/null); then
  echo "check-package-todo-growth: sin ancestro común entre '$base_ref' y HEAD (historial incompleto)" >&2
  exit 2
fi

pathspec=(':(glob)**/package_todo.yml')

# Lines added in tracked files (new files count too)...
added=$(git diff --no-ext-diff -U0 "$base" -- "${pathspec[@]}" | grep -E '^\+' | grep -vE '^\+\+\+ ' || true)
# ...and in new files not yet tracked.
while IFS= read -r untracked; do
  [ -n "$untracked" ] && added+=$'\n'"$(sed 's/^/+/' "$untracked")"
done < <(git ls-files --others --exclude-standard -- "${pathspec[@]}")

added=$(printf '%s' "$added" | sed '/^$/d')
if [ -n "$added" ]; then
  count=$(printf '%s\n' "$added" | wc -l | tr -d ' ')
  echo "FALLA: el cambio agrega $count línea(s) a package_todo.yml (base: $(git rev-parse --short "$base"), de $base_ref):" >&2
  git diff --no-ext-diff -U0 "$base" -- "${pathspec[@]}" >&2 || true
  echo "Las violaciones de packwerk no se aceptan: corrige la dependencia en lugar de registrarla." >&2
  exit 1
fi

echo "ok: ningún package_todo.yml crece respecto de $base_ref ($(git rev-parse --short "$base"))"
