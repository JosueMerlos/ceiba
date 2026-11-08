#!/usr/bin/env bash
# Verifica los `uses:` de los workflows: cada acción debe fijarse a un SHA de COMMIT de 40 hex con
# la versión en un comentario (`uses: owner/repo@<sha> # vX.Y.Z`).
#
# Trampa: en tags anotados, `git ls-remote` muestra primero el SHA del objeto tag (no sirve como
# pin; GitHub lo rechaza o resuelve mal). El commit es la línea `refs/tags/<tag>^{}`.
#
# Offline: solo comprueba el formato. Con red (por defecto) además confirma contra el remoto que el
# SHA es el commit del tag declarado. Sin red: ONLINE=0, o avisa y sigue si el remoto no responde.
# Uso: check-action-pins.sh [raíz-del-repo]
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root"
online="${ONLINE:-1}"
failures=0

while IFS=: read -r file _ line; do
  [ -n "$file" ] || continue
  # `uses: ./local` y `uses: docker://` no se fijan por SHA.
  if [[ ! "$line" =~ uses:[[:space:]]+([A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)@([^[:space:]]+)([[:space:]]+#[[:space:]]*(v?[0-9][^[:space:]]*))? ]]; then
    echo "FALLA $file: 'uses' no reconocido: $line" >&2; failures=$((failures + 1)); continue
  fi
  repo="${BASH_REMATCH[1]}"; sha="${BASH_REMATCH[2]}"; tag="${BASH_REMATCH[4]:-}"
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]] || [ -z "$tag" ]; then
    echo "FALLA $file: $repo debe fijarse a un SHA de 40 hex con '# vX.Y.Z' (tiene '$sha')" >&2
    failures=$((failures + 1)); continue
  fi
  if [ "$online" = "1" ]; then
    refs=$(git ls-remote "https://github.com/${repo}.git" "refs/tags/${tag}" "refs/tags/${tag}^{}" 2>/dev/null || true)
    if [ -z "$refs" ]; then echo "aviso $repo@$tag: sin acceso al remoto, solo se validó el formato" >&2; continue; fi
    # Si hay línea ^{} (tag anotado) el commit es esa; si no, el tag es ligero y apunta al commit.
    commit=$(awk '/\^\{\}$/ { print $1 }' <<<"$refs"); commit="${commit:-$(awk '{ print $1; exit }' <<<"$refs")}"
    if [ "$commit" != "$sha" ]; then
      echo "FALLA $file: $repo@$tag debería ser el commit $commit, no $sha" >&2; failures=$((failures + 1)); continue
    fi
  fi
  echo "ok    $repo@$tag"
done < <(grep -rn --include='*.yml' -E '^\s*-?\s*uses:' .github | sed -E 's/^([^:]+):([0-9]+):/\1:\2:/')

[ "$failures" -eq 0 ] || { echo "$failures acción(es) mal fijadas" >&2; exit 1; }
echo "acciones fijadas correctamente"
