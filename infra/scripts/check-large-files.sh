#!/usr/bin/env bash
# Fails when the change adds a binary over 100 KiB or any file over 1 MiB.
# A blob that enters history stays there forever, even if a later commit deletes it, so every blob the branch
# introduces is checked, not only the final tree. Screenshots, videos and PR evidence belong in the PR, not in git.
#
#   infra/scripts/check-large-files.sh [base]
#
# Base resolution matches check-package-todo-growth.sh: PR -> origin/<target>, push to main -> previous SHA
# (000... on a first push -> HEAD~1), local -> main. Needs fetch-depth: 0 in CI.
# Exceptions: infra/scripts/large-files-allowlist.txt, one "<glob> | <reason>" per line; the reason is mandatory.
set -euo pipefail

max_binary_kib=100
max_file_kib=1024

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"
allowlist_file="infra/scripts/large-files-allowlist.txt"

base_ref="${1:-${BASE_REF:-}}"
if [ -z "$base_ref" ]; then
  for candidate in main origin/main; do
    if git rev-parse --verify --quiet "$candidate^{commit}" >/dev/null; then base_ref=$candidate; break; fi
  done
fi
if [[ "$base_ref" =~ ^0+$ ]]; then
  if git rev-parse --verify --quiet "HEAD~1^{commit}" >/dev/null; then
    base_ref="HEAD~1"
  else
    echo "aviso: primer push sin commit previo; se omite la revisión de archivos grandes" >&2
    exit 0
  fi
fi
if [ -z "$base_ref" ] || ! git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
  echo "check-large-files: no existe la referencia base '${base_ref:-main}' (¿falta fetch-depth: 0 o git fetch?)" >&2
  exit 2
fi
if ! base=$(git merge-base "$base_ref" HEAD 2>/dev/null); then
  echo "check-large-files: sin ancestro común entre '$base_ref' y HEAD (historial incompleto)" >&2
  exit 2
fi

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

allowed_globs=()
if [ -f "$allowlist_file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    glob=$(trim "${line%%|*}")
    reason=""
    [[ "$line" == *"|"* ]] && reason=$(trim "${line#*|}")
    if [ -z "$glob" ] || [ -z "$reason" ]; then
      echo "check-large-files: entrada sin motivo en $allowlist_file: '$line' (formato: <glob> | <motivo>)" >&2
      exit 2
    fi
    allowed_globs+=("$glob")
  done < "$allowlist_file"
fi

is_allowed() {
  local glob
  for glob in "${allowed_globs[@]+"${allowed_globs[@]}"}"; do
    # shellcheck disable=SC2053 # the glob must stay unquoted to match as a pattern
    [[ "$1" == $glob ]] && return 0
  done
  return 1
}

# Same heuristic as git: a NUL byte in the first 8000 bytes means binary. `|| true` absorbs SIGPIPE from head.
stream_is_binary() {
  local sample
  sample=$(head -c 8000 | LC_ALL=C tr -d '\000' | wc -c || true)
  [ "$sample" -ne "$1" ]
}

violations=()
check() { # check <path> <bytes> <binary: 0|1>
  local path=$1 bytes=$2 binary=$3
  is_allowed "$path" && return 0
  if [ "$binary" = 1 ] && [ "$bytes" -gt $((max_binary_kib * 1024)) ]; then
    violations+=("$(printf '%6d KiB  binario  %s' $((bytes / 1024)) "$path")")
  elif [ "$bytes" -gt $((max_file_kib * 1024)) ]; then
    violations+=("$(printf '%6d KiB  texto    %s' $((bytes / 1024)) "$path")")
  fi
}

# 1) Every blob the branch introduces, including those deleted again before the merge.
while read -r type sha bytes path; do
  [ "$type" = blob ] || continue
  [ "$bytes" -gt $((max_binary_kib * 1024)) ] || continue
  head_bytes=$(( bytes < 8000 ? bytes : 8000 ))
  binary=0
  { git cat-file blob "$sha" || true; } | stream_is_binary "$head_bytes" && binary=1
  check "$path" "$bytes" "$binary"
done < <(git rev-list --objects "$base"..HEAD | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)')

# 2) Uncommitted work: tracked changes and untracked files that are not gitignored.
while IFS= read -r -d '' path; do
  [ -f "$path" ] || continue
  bytes=$(wc -c < "$path" | tr -d ' ')
  [ "$bytes" -gt $((max_binary_kib * 1024)) ] || continue
  head_bytes=$(( bytes < 8000 ? bytes : 8000 ))
  binary=0
  stream_is_binary "$head_bytes" < "$path" && binary=1
  check "$path" "$bytes" "$binary"
done < <(git diff -z --name-only HEAD; git ls-files -z --others --exclude-standard)

if [ "${#violations[@]}" -gt 0 ]; then
  echo "FALLA: el cambio agrega archivos grandes (base: $(git rev-parse --short "$base"), de $base_ref):" >&2
  printf '  %s\n' "${violations[@]}" >&2
  echo "Límites: binarios ${max_binary_kib} KiB, cualquier archivo ${max_file_kib} KiB. Capturas, videos y evidencia van" >&2
  echo "adjuntos al PR, no en git. Un blob ya commiteado queda en el historial aunque lo borres: reescribe la rama antes" >&2
  echo "del merge. Excepción justificada: '<glob> | <motivo>' en $allowlist_file." >&2
  exit 1
fi

echo "ok: ningún binario > ${max_binary_kib} KiB ni archivo > ${max_file_kib} KiB respecto de $base_ref ($(git rev-parse --short "$base"))"
