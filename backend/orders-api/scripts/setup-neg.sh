#!/usr/bin/env bash
# Create Serverless NEGs for regional Cloud Run (orders-api) and a global backend service.
# Idempotent: skips creation when resources already exist (name-based).
#
# Prerequisites:
#   - gcloud configured; Cloud Run service "orders-api" deployed in both regions.
#   - APIs: compute.googleapis.com
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   ./scripts/setup-neg.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_ID="${GCP_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Set GCP_PROJECT_ID or: gcloud config set project PROJECT_ID" >&2
  exit 1
fi

CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-orders-api}"

NEG_EU="${NEG_EU:-orders-api-eu}"
NEG_ME="${NEG_ME:-orders-api-me}"
REGION_EU="${REGION_EU:-europe-west1}"
REGION_ME="${REGION_ME:-me-central1}"

BACKEND_SERVICE="${BACKEND_SERVICE:-orders-api-backend}"

gcloud config set project "${PROJECT_ID}" >/dev/null

ensure_neg() {
  local name="$1"
  local region="$2"
  if gcloud compute network-endpoint-groups describe "${name}" --region="${region}" &>/dev/null; then
    echo "NEG exists: ${name} (${region})"
  else
    echo "Creating NEG ${name} (${region}) → Cloud Run ${CLOUD_RUN_SERVICE}"
    gcloud compute network-endpoint-groups create "${name}" \
      --region="${region}" \
      --network-endpoint-type=serverless \
      --cloud-run-service="${CLOUD_RUN_SERVICE}"
  fi
}

ensure_neg "${NEG_EU}" "${REGION_EU}"
ensure_neg "${NEG_ME}" "${REGION_ME}"

if gcloud compute backend-services describe "${BACKEND_SERVICE}" --global &>/dev/null; then
  echo "Backend service exists: ${BACKEND_SERVICE}"
else
  echo "Creating global backend service ${BACKEND_SERVICE}"
  gcloud compute backend-services create "${BACKEND_SERVICE}" \
    --global \
    --load-balancing-scheme=EXTERNAL_MANAGED \
    --protocol=HTTP
fi

add_backend() {
  local neg="$1"
  local region="$2"
  local groups
  groups="$(gcloud compute backend-services describe "${BACKEND_SERVICE}" --global \
    --format='value(backends[].group)' 2>/dev/null || true)"
  if echo "${groups}" | grep -qF "${neg}"; then
    echo "Backend already attached: ${neg} (${region})"
    return 0
  fi
  echo "Attaching NEG ${neg} (${region}) to ${BACKEND_SERVICE}"
  gcloud compute backend-services add-backend "${BACKEND_SERVICE}" \
    --global \
    --network-endpoint-group="${neg}" \
    --network-endpoint-group-region="${region}"
}

add_backend "${NEG_EU}" "${REGION_EU}"
add_backend "${NEG_ME}" "${REGION_ME}"

echo ""
echo "Done. Backend service: ${BACKEND_SERVICE}"
echo "Next: run scripts/setup-global-lb-https.sh (URL map, proxy, forwarding rule, SSL)."
