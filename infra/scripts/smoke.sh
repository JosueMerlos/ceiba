#!/usr/bin/env bash
# Smoke check of the running environment, always through the proxy (same origin).
# Usage: ./infra/scripts/smoke.sh   (PROXY_PORT and MAILPIT_PORT for different ports)
set -euo pipefail

proxy="http://localhost:${PROXY_PORT:-8080}"
mailpit="http://localhost:${MAILPIT_PORT:-8025}"
failures=0

check() { # description, command...
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "ok    $description"; else echo "FALLA $description"; failures=$((failures + 1)); fi
}
status_is() { [ "$(curl -s -o /dev/null -w '%{http_code}' "$2")" = "$1" ]; }
body_has() { curl -fsS "$2" | grep -q "$1"; }

check "GET /api/health -> 200"                    status_is 200 "$proxy/api/health"
check "GET /api/health -> {\"status\":\"ok\"}"    body_has '"status":"ok"' "$proxy/api/health"
check "GET /api/ready -> 200"                     status_is 200 "$proxy/api/ready"
check "GET / sirve el panel"                      body_has "Ceiba · Panel" "$proxy/"
check "GET /c/demo sirve booking"                 body_has "Ceiba · Reserva pública" "$proxy/c/demo"
header_has() { curl -fsSI "$2" | grep -qi "^$1"; }
check "GET / lleva la CSP en modo reporte (panel)"  header_has "content-security-policy-report-only:" "$proxy/"
check "GET /api/health lleva nosniff y frame-ancestors"  bash -c "curl -fsSI '$proxy/api/health' | grep -qi '^x-content-type-options: nosniff' && curl -fsSI '$proxy/api/health' | grep -qi \"^content-security-policy: frame-ancestors 'none'\""
check "Mailpit UI accesible"                      status_is 200 "$mailpit/"

# The HMR websocket upgrade must pass through the proxy (101 Switching Protocols).
ws_status() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 3 \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' -H 'Sec-WebSocket-Protocol: vite-hmr' "$1" || true
}
check "HMR websocket del panel (101)"   [ "$(ws_status "$proxy/?token=smoke")" = "101" ]
check "HMR websocket de booking (101)"  [ "$(ws_status "$proxy/c/?token=smoke")" = "101" ]

[ "$failures" -eq 0 ] && echo "Todo en orden." || { echo "$failures verificación(es) fallaron."; exit 1; }
