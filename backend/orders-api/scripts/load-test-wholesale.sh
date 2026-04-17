#!/usr/bin/env bash
set -euo pipefail

# Wholesale stress simulation (sequential curl only).

BASE_URL="${BASE_URL:-http://localhost:8080}"
N="${N:-100}" # 50-500 recommended
MOCK_MODE="${MOCK_MODE:-1}"
TOKEN="${TOKEN:-}"
INTERNAL_API_KEY="${INTERNAL_API_KEY:-}"

BASE_URL="${BASE_URL%/}"
if (( N < 50 || N > 500 )); then
  echo "N must be between 50 and 500"
  exit 1
fi

AUTH_HEADERS=()
if [[ -n "${TOKEN}" ]]; then
  AUTH_HEADERS+=(-H "Authorization: Bearer ${TOKEN}")
fi
INTERNAL_HEADERS=()
if [[ -n "${INTERNAL_API_KEY}" ]]; then
  INTERNAL_HEADERS+=(-H "x-internal-api-key: ${INTERNAL_API_KEY}")
fi

stress_get() {
  local path="$1"
  local label="$2"
  local ok=0 fail=0 total_ms=0
  for ((i=1; i<=N; i++)); do
    local out code time_s ms
    out="$(curl -sS -o /dev/null -w "%{http_code} %{time_total}" "${AUTH_HEADERS[@]}" "${BASE_URL}${path}" || echo "000 0")"
    code="${out%% *}"
    time_s="${out##* }"
    ms="$(awk "BEGIN {print int(${time_s} * 1000)}")"
    total_ms=$((total_ms + ms))
    if [[ "${code}" =~ ^2 ]]; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done
  echo "${label}: 2xx=${ok} other=${fail} avg_ms=$((total_ms / N))"
}

stress_post() {
  local path="$1"
  local label="$2"
  local body="$3"
  local ok=0 fail=0 total_ms=0
  for ((i=1; i<=N; i++)); do
    local out code time_s ms
    out="$(curl -sS -o /dev/null -w "%{http_code} %{time_total}" -X POST "${AUTH_HEADERS[@]}" \
      -H "content-type: application/json" -d "${body}" "${BASE_URL}${path}" || echo "000 0")"
    code="${out%% *}"
    time_s="${out##* }"
    ms="$(awk "BEGIN {print int(${time_s} * 1000)}")"
    total_ms=$((total_ms + ms))
    if [[ "${code}" =~ ^2|^4 ]]; then ok=$((ok+1)); else fail=$((fail+1)); fi
  done
  echo "${label}: 2xx/4xx=${ok} other=${fail} avg_ms=$((total_ms / N))"
}

echo "BASE_URL=${BASE_URL}"
echo "N=${N} MOCK_MODE=${MOCK_MODE}"
echo ""

stress_get "/wholesale/products?limit=20" "GET /wholesale/products"
stress_get "/admin/kpis" "GET /admin/kpis"

if [[ "${MOCK_MODE}" == "1" ]]; then
  stress_post "/wholesale/orders" "POST /wholesale/orders (mock invalid safe)" '{"wholesalerId":"","storeId":"mock","storeName":"mock","items":[],"dryRun":true}'
else
  stress_post "/wholesale/orders" "POST /wholesale/orders" '{"wholesalerId":"replace-with-real-id","storeId":"store-load","storeName":"Load Test Store","items":[{"productId":"p1","qty":1}]}'
fi

echo ""
echo "Global health snapshot (latency/outbox lag/db/cache metrics):"
curl -sS "${INTERNAL_HEADERS[@]}" "${BASE_URL}/internal/ops/global-health" || true
echo ""

