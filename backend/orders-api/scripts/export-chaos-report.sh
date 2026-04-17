#!/usr/bin/env bash
# Fetch GET /internal/ops/dashboard/chaos-report and save JSON (requires internal API key).
#
# Usage:
#   export SEARCH_INTERNAL_API_KEY=your-key
#   export BASE_URL=http://localhost:8080
#   ./scripts/export-chaos-report.sh
#   OUT_FILE=./reports/chaos-report.json ./scripts/export-chaos-report.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BASE_URL="${BASE_URL:-http://localhost:8080}"
KEY="${SEARCH_INTERNAL_API_KEY:-}"
if [[ -z "${KEY}" ]]; then
  echo "Set SEARCH_INTERNAL_API_KEY (same value as the server env)." >&2
  exit 1
fi

OUT_FILE="${OUT_FILE:-${ROOT_DIR}/chaos-report-$(date +%Y%m%d-%H%M%S).json}"
mkdir -p "$(dirname "${OUT_FILE}")"

URL="${BASE_URL%/}/internal/ops/dashboard/chaos-report"

echo "GET ${URL}"
curl -sS -f -H "x-internal-api-key: ${KEY}" -H "Accept: application/json" "${URL}" | tee "${OUT_FILE}"
echo ""
echo "Wrote: ${OUT_FILE}"
