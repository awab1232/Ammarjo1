#!/usr/bin/env bash
set -uo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
N="${N:-100}"
MOCK_MODE="${MOCK_MODE:-1}"
INTERNAL_API_KEY="${INTERNAL_API_KEY:-}"

BASE_URL="${BASE_URL%/}"

if (( N < 1 )); then
  echo "N must be >= 1"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_TS="$(date +%s)"

run_step() {
  local label="$1"
  local script_path="$2"
  echo "==> Running ${label}: ${script_path}"
  N="${N}" MOCK_MODE="${MOCK_MODE}" BASE_URL="${BASE_URL}" INTERNAL_API_KEY="${INTERNAL_API_KEY}" bash "${script_path}"
  return $?
}

orders_code=0
service_code=0
wholesale_code=0

run_step "Orders load test" "${SCRIPT_DIR}/load-test-orders.sh" || orders_code=$?
run_step "Service requests load test" "${SCRIPT_DIR}/load-test-service-requests.sh" || service_code=$?
run_step "Wholesale load test" "${SCRIPT_DIR}/load-test-wholesale.sh" || wholesale_code=$?

HEALTH_HEADERS=()
if [[ -n "${INTERNAL_API_KEY}" ]]; then
  HEALTH_HEADERS+=(-H "x-internal-api-key: ${INTERNAL_API_KEY}")
fi

health_json="$(curl -sS "${HEALTH_HEADERS[@]}" "${BASE_URL}/internal/ops/global-health" 2>/dev/null || echo '{}')"

readiness_line="$(
  printf '%s' "${health_json}" | node -e "
const fs = require('fs');
const raw = fs.readFileSync(0, 'utf8') || '{}';
let data = {};
try { data = JSON.parse(raw); } catch { data = {}; }
const ready = data.isProductionReady === true ? 'true' : 'false';
const score = Number.isFinite(Number(data.systemScore)) ? Number(data.systemScore) : 0;
const warnings = Array.isArray(data.criticalWarnings) ? data.criticalWarnings.join(' | ') : '';
process.stdout.write(ready + '\\n' + String(score) + '\\n' + warnings);
")"

is_ready="$(printf '%s' "${readiness_line}" | awk 'NR==1{print}')"
system_score="$(printf '%s' "${readiness_line}" | awk 'NR==2{print}')"
critical_warnings="$(printf '%s' "${readiness_line}" | awk 'NR>=3{print}')"

END_TS="$(date +%s)"
TOTAL_SEC="$((END_TS - START_TS))"

status_text() {
  local code="$1"
  if [[ "${code}" -eq 0 ]]; then
    echo "PASS"
  else
    echo "FAIL(${code})"
  fi
}

ready_text="NO"
if [[ "${is_ready}" == "true" ]]; then
  ready_text="YES"
fi

echo ""
echo "================ PHASE 7 VALIDATION SUMMARY ================"
printf "%-38s | %s\n" "Orders load test status" "$(status_text "${orders_code}")"
printf "%-38s | %s\n" "Service requests load test status" "$(status_text "${service_code}")"
printf "%-38s | %s\n" "Wholesale load test status" "$(status_text "${wholesale_code}")"
printf "%-38s | %s\n" "System score" "${system_score}"
printf "%-38s | %s\n" "Production ready" "${ready_text}"
printf "%-38s | %ss\n" "Total execution time" "${TOTAL_SEC}"
printf "%-38s | %s\n" "Critical warnings" "${critical_warnings:-none}"
echo "============================================================"

if [[ "${orders_code}" -eq 0 && "${service_code}" -eq 0 && "${wholesale_code}" -eq 0 && "${is_ready}" == "true" ]]; then
  exit 0
fi

exit 1

