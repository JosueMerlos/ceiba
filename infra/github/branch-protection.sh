#!/usr/bin/env bash
# Protección de la rama main (M0.02). LISTO PARA CORRER cuando exista el remoto en GitHub.
#
#   infra/github/branch-protection.sh <owner>/<repo>            # muestra el payload, no cambia nada
#   APPLY=1 infra/github/branch-protection.sh <owner>/<repo>    # lo aplica con `gh api` (requiere admin)
#
# Requiere `gh` autenticado. app_id 15368 = GitHub Actions (el check solo cuenta si lo publica esa app). Los nombres de los checks son los de los jobs de
# .github/workflows/ci.yml y .github/workflows/pr-title.yml.
#
# TODO(CODEOWNERS): con un solo desarrollador, `require_code_owner_reviews` queda en false (GitHub no permite
# aprobar el PR propio). Cuando haya una segunda persona, activar A LA VEZ `require_code_owner_reviews: true`
# y `required_approving_review_count >= 1`; uno sin el otro no protege nada. Mientras tanto, el guardián real
# del aislamiento de packs es spec/packs/pack_contract_spec.rb (check requerido dentro de backend-test).
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
      { "context": "backend-test", "app_id": 15368 },
      { "context": "backend-security", "app_id": 15368 },
      { "context": "frontend-lint", "app_id": 15368 },
      { "context": "frontend-test", "app_id": 15368 },
      { "context": "frontend-security", "app_id": 15368 },
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
# Además, en Settings > General > Pull Requests: permitir solo "Squash merging" con el título del PR
# como mensaje del commit (así el título validado es el que queda en main) y "Automatically delete head branches".
