#!/usr/bin/env bash
# Smoke-test internal ops + alert *read* paths. Does not fabricate DLQ data (requires real DB state).
#
# Usage:
#   export SEARCH_INTERNAL_API_KEY=your-key
#   export BASE_URL=http://localhost:3000
#   ./scripts/test-alerts.sh
#
# Optional: test manual retry endpoint with a random UUID (expects 404 if event does not exist):
#   TEST_RETRY_PROBE=1 ./scripts/test-alerts.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${BASE_URL:-http://localhost:3000}"
KEY="${SEARCH_INTERNAL_API_KEY:-}"

if [[ -z "${KEY}" ]]; then
  echo "Set SEARCH_INTERNAL_API_KEY (same as server env)." >&2
  exit 1
fi

HDR=(-H "x-internal-api-key: ${KEY}" -H "Accept: application/json")

echo "==> GET /health (no key)"
curl -sS "${BASE_URL%/}/health" | head -c 400 || true
echo ""
echo ""

echo "==> GET /internal/ops/global-health"
curl -sS -f "${HDR[@]}" "${BASE_URL%/}/internal/ops/global-health" | head -c 800 || true
echo ""
echo ""

echo "==> GET /internal/ops/dashboard/summary?hours=24"
curl -sS -f "${HDR[@]}" "${BASE_URL%/}/internal/ops/dashboard/summary?hours=24" | head -c 1200 || true
echo ""
echo ""

echo "==> GET /internal/ops/dashboard/alerts-history?limit=20"
curl -sS -f "${HDR[@]}" "${BASE_URL%/}/internal/ops/dashboard/alerts-history?limit=20" | head -c 1200 || true
echo ""
echo ""

if [[ "${TEST_RETRY_PROBE:-}" == "1" ]]; then
  FAKE_ID="00000000-0000-4000-8000-000000000001"
  echo "==> POST /internal/events/retry/${FAKE_ID} (expect 404 if row missing)"
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST "${HDR[@]}" \
    "${BASE_URL%/}/internal/events/retry/${FAKE_ID}" || true
  echo ""
  echo "(A real retry would fire notifyManualRetryOne when alerting + destinations are configured.)"
fi

echo ""
echo "Done. To exercise real DLQ alerts: use failing handlers, chaos (CHAOS_TESTING.md), or retry real failed event IDs from GET /internal/events/dashboard."
