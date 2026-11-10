#!/usr/bin/env bash
# Checks the workflows' `uses:` lines: each action must be pinned to a 40-hex COMMIT SHA with the version in a comment
# (`uses: owner/repo@<sha> # vX.Y.Z`).
#
# Trap: for annotated tags, `git ls-remote` lists the tag object's SHA first, which is no good as a pin (GitHub rejects
# or mis-resolves it). The commit is the `refs/tags/<tag>^{}` line.
#
# Offline: only the format is checked. With network (default) it also confirms against the remote that the SHA is the
# declared tag's commit. Skip the network with ONLINE=0; it warns and continues if the remote does not answer.
# Usage: check-action-pins.sh [repo-root]
set -euo pipefail
root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$root"
online="${ONLINE:-1}"
failures=0

export GIT_TERMINAL_PROMPT=0
# Queries the remote. Codes: 0 = ok (output may be empty: the tag does not exist), 1 = FAILURE (repo does not exist),
# 2 = no network or another error (warning only).
remote_refs() { # remote_refs <repo> <tag>  -> prints the refs and returns 0/1/2
  local out err_file rc=0
  err_file=$(mktemp)
  out=$(git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=10 ls-remote "https://github.com/$1.git" \
    "refs/tags/$2" "refs/tags/$2^{}" 2>"$err_file") || rc=$?
  if [ "$rc" -ne 0 ] && grep -qi "not found" "$err_file"; then rm -f "$err_file"; return 1; fi
  rm -f "$err_file"
  [ "$rc" -eq 0 ] || return 2
  printf '%s' "$out"
}

# One line per unique `uses:`: file<TAB>content (no line number, to deduplicate).
while IFS=$'\t' read -r file line; do
  [ -n "$file" ] || continue
  # `uses: ./local` and `uses: docker://` are not pinned by SHA.
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
    # With a ^{} line (annotated tag) that is the commit; otherwise the tag is lightweight and points at the commit.
    commit=$(awk '/\^\{\}$/ { print $1 }' <<<"$refs"); commit="${commit:-$(awk '{ print $1; exit }' <<<"$refs")}"
    if [ "$commit" != "$sha" ]; then
      echo "FALLA $file: $repo@$tag debería ser el commit $commit, no $sha" >&2; failures=$((failures + 1)); continue
    fi
  fi
  echo "ok    $repo@$tag"
done < <(grep -rnH --include='*.yml' -E '^\s*-?\s*uses:' .github | sed -E 's/^([^:]+):[0-9]+:/\1\t/' | sort -u)

[ "$failures" -eq 0 ] || { echo "$failures acción(es) mal fijadas" >&2; exit 1; }
echo "acciones fijadas correctamente"
