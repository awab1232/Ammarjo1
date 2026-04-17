#!/usr/bin/env bash
# Lightweight smoke / stress check against orders-api (no k6). Safe defaults: low request count.
#
# Usage:
#   export BASE_URL=https://your-service.run.app
#   ./scripts/load-test.sh
#
# Optional:
#   N=200 ./scripts/load-test.sh
#
# Notes:
# - GET /health — no auth.
# - GET /search/products — requires Algolia configured; may return 503 if not.
# - POST /orders requires Firebase Bearer token — not invoked here; use k6/Artillery for auth load tests.
#
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
N="${N:-50}"

BASE_URL="${BASE_URL%/}"

echo "BASE_URL=${BASE_URL}"
echo "N=${N} (requests per endpoint)"
echo ""

hit() {
  local path="$1"
  local label="$2"
  local ok=0
  local fail=0
  local i
  for ((i = 1; i <= N; i++)); do
    local code
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 15 "${BASE_URL}${path}" || echo "000")"
    if [[ "${code}" =~ ^2 ]]; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done
  echo "${label}: 2xx=${ok} other=${fail}"
}

hit "/health" "GET /health"
hit "/search/products?q=test&hitsPerPage=5" "GET /search/products"

echo ""
echo "Done. If search shows many non-2xx, ensure ALGOLIA_* is set on the server."
