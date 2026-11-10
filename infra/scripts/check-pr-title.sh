#!/usr/bin/env bash
# Validates that a PR title follows conventional commits: type(optional scope)!: subject
# It is the ONLY definition of the rule: used by the pr-title.yml workflow and bin/ci.
# Usage: check-pr-title.sh "feat(backend): add readiness check"
set -euo pipefail

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
pattern="^(${types})(\\([a-z0-9._/-]+\\))?!?: [^[:space:]].*\$"
title="${1-}"

# A single-line title (a newline would make the regex evaluate only the first line).
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
