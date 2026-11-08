#!/usr/bin/env bash
# Falla si el cambio AGREGA líneas a algún package_todo.yml (docs/architecture/02-modular-monolith.md,
# regla 4: las violaciones no se "aceptan para después"). Solo se permite que la deuda baje.
#
#   infra/scripts/check-package-todo-growth.sh [base]
#
# Compara el árbol de trabajo (cambios sin commitear incluidos) con el merge-base entre `base` y HEAD:
#   - en un PR de CI:  base = origin/<rama destino>  (CI pasa BASE_REF)
#   - en un push a main: base = el SHA anterior al push (CI pasa BASE_REF); si es 000... (primer push), HEAD~1
#   - en local: base = main (u origin/main si existe y main no)
# Requiere historial suficiente para calcular el merge-base (en CI: fetch-depth: 0).
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

base_ref="${1:-${BASE_REF:-}}"
if [ -z "$base_ref" ]; then
  for candidate in main origin/main; do
    if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then base_ref=$candidate; break; fi
  done
fi
# Primer push de una rama (p. ej. el primero a main): GitHub informa el SHA previo como 40 ceros.
# Se compara con el padre de HEAD; si no hay (un solo commit), no hay contra qué comparar.
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

# Líneas agregadas en archivos versionados (cuenta también los archivos nuevos)...
added=$(git diff --no-ext-diff -U0 "$base" -- "${pathspec[@]}" | grep -E '^\+' | grep -vE '^\+\+\+ ' || true)
# ...y en archivos nuevos sin versionar todavía.
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
