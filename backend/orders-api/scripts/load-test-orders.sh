#!/usr/bin/env bash
set -euo pipefail

# Orders/Admin load simulation (sequential curl only).
# Safe-by-default: MOCK_MODE=1 sends invalid POST payloads to avoid data mutation.

BASE_URL="${BASE_URL:-http://localhost:3000}"
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

run_get() {
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

run_post() {
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

run_get "/admin/kpis" "GET /admin/kpis"
run_get "/internal/analytics/summary" "GET /internal/analytics/summary"

if [[ "${MOCK_MODE}" == "1" ]]; then
  run_post "/ratings" "POST /ratings (mock invalid safe)" '{"targetType":"technician","targetId":"mock-tech","rating":0,"reviewText":"load-test-mock","dryRun":true}'
else
  run_post "/ratings" "POST /ratings" '{"targetType":"technician","targetId":"demo-tech","rating":5,"reviewText":"load test run"}'
fi

echo ""
echo "Global health snapshot (for latency/outbox/cache/db metrics):"
curl -sS "${INTERNAL_HEADERS[@]}" "${BASE_URL}/internal/ops/global-health" || true
echo ""

