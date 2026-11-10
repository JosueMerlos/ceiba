#!/usr/bin/env bash
# Protection for the main branch. READY TO RUN once the GitHub remote exists.
#
#   infra/github/branch-protection.sh <owner>/<repo>            # prints the payload, changes nothing
#   APPLY=1 infra/github/branch-protection.sh <owner>/<repo>    # applies it with `gh api` (needs admin)
#
# Needs an authenticated `gh`. app_id 15368 = GitHub Actions (a check only counts if that app publishes it). Check names
# are the job names in .github/workflows/ci.yml and .github/workflows/pr-title.yml.
#
# TODO(CODEOWNERS): with a single developer, `require_code_owner_reviews` stays false (GitHub does not allow approving
# your own PR). Once there is a second person, enable `require_code_owner_reviews: true` AND
# `required_approving_review_count >= 1` together; one without the other protects nothing. Meanwhile, the real guard for
# pack isolation is spec/packs/pack_contract_spec.rb (a required check inside backend-test).
set -euo pipefail

repo="${1:?uso: $0 <owner>/<repo>}"
branch="${BRANCH:-main}"

payload=$(cat <<JSON
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "actionlint", "app_id": 15368 },
      { "context": "backend-lint", "app_id": 15368 },
      { "context": "backend-packs", "app_id": 15368 },
      { "context": "backend-migrations", "app_id": 15368 },
      { "context": "backend-test", "app_id": 15368 },
      { "context": "backend-security", "app_id": 15368 },
      { "context": "frontend-lint", "app_id": 15368 },
      { "context": "frontend-test", "app_id": 15368 },
      { "context": "frontend-security", "app_id": 15368 },
      { "context": "api-contract", "app_id": 15368 },
      { "context": "pr-title", "app_id": 15368 }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "required_linear_history": true,
  "required_conversation_resolution": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "restrictions": null
}
JSON
)

if [ "${APPLY:-0}" != "1" ]; then
  echo "# Simulación (APPLY=1 para aplicar): PUT /repos/${repo}/branches/${branch}/protection"
  echo "$payload"
  exit 0
fi

echo "$payload" | gh api --method PUT "repos/${repo}/branches/${branch}/protection" --input -
echo "Rama ${branch} de ${repo} protegida."
# Also, in Settings > General > Pull Requests: allow only "Squash merging" with the PR title as the commit message (so
# the validated title is the one that lands on main) and "Automatically delete head branches".
