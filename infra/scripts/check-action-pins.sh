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

export GIT_TERMINAL_PROMPT=0
# Consulta el remoto. Códigos: 0 = ok (puede no haber salida: el tag no existe), 1 = FALLA (repo
# inexistente), 2 = sin red u otro error (solo aviso).
remote_refs() { # remote_refs <repo> <tag>  -> imprime las refs y devuelve 0/1/2
  local out err_file rc=0
  err_file=$(mktemp)
  out=$(git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 ls-remote "https://github.com/$1.git" \
    "refs/tags/$2" "refs/tags/$2^{}" 2>"$err_file") || rc=$?
  if [ "$rc" -ne 0 ] && grep -qi "not found" "$err_file"; then rm -f "$err_file"; return 1; fi
  rm -f "$err_file"
  [ "$rc" -eq 0 ] || return 2
  printf '%s' "$out"
}

# Una línea por `uses:` único: archivo<TAB>contenido (sin número de línea, para deduplicar).
while IFS=$'\t' read -r file line; do
  [ -n "$file" ] || continue
  # `uses: ./local` y `uses: docker://` no se fijan por SHA.
  if [[ "$line" =~ uses:[[:space:]]+(\./|docker://) ]]; then echo "salto $line"; continue; fi
  if [[ ! "$line" =~ uses:[[:space:]]+([A-Za-z0-9._-]+/[A-Za-z0-9._/-]+)@([^[:space:]]+)([[:space:]]+#[[:space:]]*(v?[0-9][^[:space:]]*))? ]]; then
    echo "FALLA $file: 'uses' no reconocido: $line" >&2; failures=$((failures + 1)); continue
  fi
  repo="${BASH_REMATCH[1]}"; sha="${BASH_REMATCH[2]}"; tag="${BASH_REMATCH[4]:-}"
  if [[ ! "$sha" =~ ^[0-9a-f]{40}$ ]] || [ -z "$tag" ]; then
    echo "FALLA $file: $repo debe fijarse a un SHA de 40 hex con '# vX.Y.Z' (tiene '$sha')" >&2
    failures=$((failures + 1)); continue
  fi
  if [ "$online" = "1" ]; then
    rc=0; refs=$(remote_refs "$repo" "$tag") || rc=$?
    if [ "$rc" -eq 1 ]; then echo "FALLA $file: el repositorio $repo no existe" >&2; failures=$((failures + 1)); continue; fi
    if [ "$rc" -eq 2 ]; then echo "aviso $repo@$tag: sin acceso al remoto, solo se validó el formato" >&2; continue; fi
    if [ -z "$refs" ]; then echo "FALLA $file: el tag $tag no existe en $repo" >&2; failures=$((failures + 1)); continue; fi
    # Si hay línea ^{} (tag anotado) el commit es esa; si no, el tag es ligero y apunta al commit.
    commit=$(awk '/\^\{\}$/ { print $1 }' <<<"$refs"); commit="${commit:-$(awk '{ print $1; exit }' <<<"$refs")}"
    if [ "$commit" != "$sha" ]; then
      echo "FALLA $file: $repo@$tag debería ser el commit $commit, no $sha" >&2; failures=$((failures + 1)); continue
    fi
  fi
  echo "ok    $repo@$tag"
done < <(grep -rnH --include='*.yml' -E '^\s*-?\s*uses:' .github | sed -E 's/^([^:]+):[0-9]+:/\1\t/' | sort -u)

[ "$failures" -eq 0 ] || { echo "$failures acción(es) mal fijadas" >&2; exit 1; }
echo "acciones fijadas correctamente"
