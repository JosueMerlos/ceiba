#!/usr/bin/env bash
# Tests for check-pr-title.sh: valid and invalid conventional-commits titles.
set -uo pipefail
cd "$(dirname "$0")"

failures=0
expect() { # expect <valid|invalid> <title>
  local expected=$1 title=$2 actual=invalid
  ./check-pr-title.sh "$title" >/dev/null 2>&1 && actual=valid
  if [ "$actual" = "$expected" ]; then echo "ok    [$expected] $title"
  else echo "FALLA [$expected esperado, fue $actual] $title"; failures=$((failures + 1)); fi
}

expect valid   "feat: add booking page"
expect valid   "fix(backend): bound readiness checks"
expect valid   "chore(deps): bump rubocop from 1.92.1 to 1.92.2"
expect valid   "ci: add workflow"
expect valid   "refactor(api)!: rename endpoint"
expect valid   "docs: update M0.02 notes"
expect valid   "revert: undo broken migration"
expect invalid "Add booking page"
expect invalid "feature: add booking page"
expect invalid "feat add booking page"
expect invalid "feat:missing space"
expect invalid "feat(): empty scope"
expect invalid "feat: "
expect invalid "FEAT: uppercase type"
expect invalid ""
expect invalid "$(printf 'feat: first line\nsecond line')"

[ "$failures" -eq 0 ] || { echo "$failures caso(s) fallaron"; exit 1; }
echo "todos los casos pasaron"
