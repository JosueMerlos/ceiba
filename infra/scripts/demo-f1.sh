#!/usr/bin/env bash
# F1 demo, end to end over the panel API and through the proxy (same origin): books an appointment, reschedules it, cancels the
# new one, then books another and takes it through check-in to completed. It CREATES demo appointments in the database the
# environment points to and deletes nothing; it never seeds.
#
# Usage: ./infra/scripts/demo-f1.sh [email]
#   email: a receptionist (or manager) of a branch with the appointments module active; by default the demo seeds' receptionist.
#   The password is asked for (never stored here); DEMO_PASSWORD skips the prompt. PROXY_PORT changes the port.
# Requires curl and jq.
set -euo pipefail

proxy="http://localhost:${PROXY_PORT:-8080}"
email="${1:-recepcion@barberia-guegu.ceiba.test}"
jar="$(mktemp)"
trap 'rm -f "$jar"' EXIT

for tool in curl jq; do command -v "$tool" >/dev/null || { echo "Falta $tool" >&2; exit 1; }; done

if [ -z "${DEMO_PASSWORD:-}" ]; then
  read -r -s -p "Contraseña de $email: " DEMO_PASSWORD
  echo
fi

csrf=""
step() { printf '\n== %s\n' "$1"; }
# method, path, [json body]: prints the body and fails on a non-2xx status.
call() {
  local method="$1" path="$2" body="${3:-}" status output
  output="$(mktemp)"
  local args=(-s -o "$output" -w '%{http_code}' -b "$jar" -c "$jar" -X "$method" "$proxy$path" -H "Accept: application/json")
  [ -n "$csrf" ] && args+=(-H "X-CSRF-Token: $csrf")
  [ "$method" = "POST" ] && args+=(-H "Idempotency-Key: $(uuidgen)")
  [ -n "$body" ] && args+=(-H "Content-Type: application/json" --data "$body")
  status="$(curl "${args[@]}")"
  cat "$output"; rm -f "$output"
  [ "${status:0:1}" = "2" ] || { echo >&2; echo "HTTP $status en $method $path" >&2; exit 1; }
}

step "Inicio de sesión ($email)"
login="$(call POST /api/v1/auth/login "$(jq -n --arg email "$email" --arg password "$DEMO_PASSWORD" '{email: $email, password: $password}')")"
csrf="$(jq -r '.data.csrf_token' <<<"$login")"
echo "ok"

step "Contexto: organización, empresa y sucursal"
me="$(call GET /api/v1/me)"
org="$(jq -r '.data.context.organization.id' <<<"$me")"
company="$(jq -r '.data.context.company.id' <<<"$me")"
branch="$(call GET "/api/v1/organizations/$org/companies/$company/branches" | jq -r '.data[0].id')"
base="/api/v1/organizations/$org/companies/$company/appointments/branches/$branch"
echo "organización $org, empresa $company, sucursal $branch"

service="$(call GET "/api/v1/organizations/$org/companies/$company/appointments/services" | jq -r '.data[0].id')"
customer="$(call GET "/api/v1/organizations/$org/companies/$company/branches/$branch/customers" | jq -r '.data[0].id')"
from="$(date -u +%Y-%m-%d)"
to="$(date -u -v+13d +%Y-%m-%d 2>/dev/null || date -u -d '+13 days' +%Y-%m-%d)"
slots="$(call GET "$base/availability?service_ids=$service&professional_id=any&from=$from&to=$to")"
[ "$(jq '.data | length' <<<"$slots")" -ge 3 ] || { echo "No hay tres huecos libres en dos semanas" >&2; exit 1; }
slot() { jq -c ".data[$1]" <<<"$slots"; }
book_body() { jq -n --arg customer "$customer" --arg service "$service" --argjson slot "$1" \
  '{customer_id: $customer, service_ids: [$service], professional_id: $slot.professional_id, starts_at: $slot.starts_at}'; }
summary() { jq -c '.data | {id, status, starts_at, professional_id, rescheduled_from_id, cancelled_by, cancellation_reason, lock_version}'; }

step "1. Reserva"
first="$(call POST "$base/appointments" "$(book_body "$(slot 0)")")"
summary <<<"$first"
first_id="$(jq -r '.data.id' <<<"$first")"

step "2. Reprograma al siguiente hueco del mismo profesional"
target="$(jq -c --arg professional "$(jq -r '.data.professional_id' <<<"$first")" --arg taken "$(jq -r '.data.starts_at' <<<"$first")" \
  '[.data[] | select(.professional_id == $professional and .starts_at != $taken)][1]' <<<"$slots")"
moved="$(call POST "$base/appointments/$first_id/reschedule" "$(jq -n --argjson slot "$target" '{starts_at: $slot.starts_at, professional_id: $slot.professional_id}')")"
summary <<<"$moved"
moved_id="$(jq -r '.data.id' <<<"$moved")"
call GET "$base/appointments/$first_id" | summary

step "3. Cancela la cita reprogramada"
call POST "$base/appointments/$moved_id/cancel" '{"reason":"customer_request"}' | summary

step "4. Reserva otra, check-in y la completa"
fresh="$(call POST "$base/appointments" "$(book_body "$(slot 2)")")"
fresh_id="$(jq -r '.data.id' <<<"$fresh")"
call POST "$base/appointments/$fresh_id/check_in" | summary
call POST "$base/appointments/$fresh_id/complete" | summary

step "5. Agenda de esos días"
call GET "$base/appointments?from=$from&to=$to" | jq -c --arg a "$first_id" --arg b "$moved_id" --arg c "$fresh_id" \
  '[.data[] | select(.id == $a or .id == $b or .id == $c) | {id, status, starts_at}]'

echo
echo "Demo de F1 completa."
