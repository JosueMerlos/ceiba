#!/usr/bin/env bash
# Valida que un título de PR siga conventional commits: tipo(ámbito opcional)!: asunto
# Es la ÚNICA definición de la regla: la usan el workflow pr-title.yml y bin/ci.
# Uso: check-pr-title.sh "feat(backend): add readiness check"
set -euo pipefail

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
pattern="^(${types})(\\([a-z0-9._/-]+\\))?!?: [^[:space:]].*\$"
title="${1-}"

# Un título de una sola línea (un salto de línea haría que el regex solo evaluara la primera).
if [[ "$title" != *$'\n'* && "$title" =~ $pattern ]]; then
  echo "ok: el título sigue conventional commits"
  exit 0
fi

cat >&2 <<MSG
El título del PR no sigue conventional commits.
  Título:   ${title}
  Formato:  tipo(ámbito opcional)!: asunto
  Tipos:    ${types//|/, }
  Ejemplo:  feat(backend): add readiness check
MSG
exit 1
