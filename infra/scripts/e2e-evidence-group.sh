#!/usr/bin/env bash
# Prints the evidence group of a work branch: the milestone (M2.04) for feat/m2.04-<slug>, the branch slug for
# fix/<slug>, and nothing (no subfolder) for anything else, such as main or a detached HEAD.
#
#   infra/scripts/e2e-evidence-group.sh                # the current branch
#   infra/scripts/e2e-evidence-group.sh fix/error_500  # an explicit branch name
set -uo pipefail

branch=${1:-}
if [ -z "$branch" ]; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
fi

slug=${branch#feat/}
slug=${slug#fix/}
# No feat/ and no fix/ prefix (main, release, a tag...) or a detached HEAD: no group.
[ "$slug" = "$branch" ] && exit 0
[ "$slug" = "HEAD" ] && exit 0

# One directory name only: slashes and anything unusual become dashes, and a leading dot or dash is dropped.
slug=$(printf '%s' "$slug" | tr -c 'A-Za-z0-9._-' '-')
slug=${slug#${slug%%[A-Za-z0-9]*}}

shopt -s nocasematch
if [[ $slug =~ ^m([0-9]+)\.([0-9]+)(-|$) ]]; then
  printf 'M%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
else
  printf '%s\n' "$slug"
fi
