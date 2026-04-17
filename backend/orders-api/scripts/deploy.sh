#!/usr/bin/env bash
# Deploy orders-api to Google Cloud Run (Artifact Registry / GCR image + managed Cloud Run).
# Prerequisites: gcloud auth, billing enabled, APIs: run.googleapis.com, cloudbuild.googleapis.com
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   ./scripts/deploy.sh              # deploys to both regions (see REGIONS below)
#   REGION=europe-west1 ./scripts/deploy.sh
#
# Optional Secret Manager (requires secrets + IAM on orders-api-sa):
#   export USE_SECRET_MANAGER=1
#   ./scripts/deploy.sh
#
# By default, only Algolia secrets are mounted (must exist in Secret Manager):
#   ALGOLIA_APP_ID, ALGOLIA_SEARCH_API_KEY, ALGOLIA_WRITE_API_KEY
# To also mount DATABASE_URL, REDIS_URL, SEARCH_INTERNAL_API_KEY, etc., set:
#   export SECRET_MANAGER_BINDINGS='DATABASE_URL=DATABASE_URL:latest,...,ALGOLIA_APP_ID=ALGOLIA_APP_ID:latest,...'
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

PROJECT_ID="${GCP_PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
if [[ -z "${PROJECT_ID}" ]]; then
  PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
fi
if [[ -z "${PROJECT_ID}" ]]; then
  echo "Set GCP_PROJECT_ID or run: gcloud config set project YOUR_PROJECT_ID" >&2
  exit 1
fi

IMAGE="${IMAGE:-gcr.io/${PROJECT_ID}/orders-api}"
SERVICE_NAME="${SERVICE_NAME:-orders-api}"

# Optional: mount Secret Manager as env vars (requires SA with secretAccessor). Unset = unchanged behavior.
# export USE_SECRET_MANAGER=1
# export SERVICE_ACCOUNT_EMAIL=orders-api-sa@${PROJECT_ID}.iam.gserviceaccount.com
USE_SECRET_MANAGER="${USE_SECRET_MANAGER:-0}"
SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_EMAIL:-orders-api-sa@${PROJECT_ID}.iam.gserviceaccount.com}"

# Comma-separated Cloud Run --set-secrets: ENV_VAR_NAME=SECRET_RESOURCE_ID:version
# Default: Algolia only (override SECRET_MANAGER_BINDINGS to append DB, Redis, internal API key, etc.).
SECRET_MANAGER_BINDINGS="${SECRET_MANAGER_BINDINGS:-ALGOLIA_APP_ID=ALGOLIA_APP_ID:latest,ALGOLIA_SEARCH_API_KEY=ALGOLIA_SEARCH_API_KEY:latest,ALGOLIA_WRITE_API_KEY=ALGOLIA_WRITE_API_KEY:latest}"

# Primary (EU) + Middle East — same image; routing/global LB is a later phase.
REGIONS_DEFAULT="europe-west1 me-central1"
REGIONS="${REGION:+${REGION}}"
if [[ -z "${REGIONS}" ]]; then
  REGIONS="${REGIONS_DEFAULT}"
fi

echo "Project: ${PROJECT_ID}"
echo "Image:   ${IMAGE}"
echo "Regions: ${REGIONS}"

echo "==> Cloud Build: push image"
gcloud builds submit --project "${PROJECT_ID}" --tag "${IMAGE}" "${ROOT_DIR}"

deploy_one() {
  local r="$1"
  echo "==> Cloud Run deploy: ${SERVICE_NAME} @ ${r}"
  if [[ "${USE_SECRET_MANAGER}" == "1" ]]; then
    echo "    (Secret Manager: enabled, service account: ${SERVICE_ACCOUNT_EMAIL})"
    gcloud run deploy "${SERVICE_NAME}" \
      --project "${PROJECT_ID}" \
      --image "${IMAGE}" \
      --platform managed \
      --region "${r}" \
      --allow-unauthenticated \
      --port 3000 \
      --service-account "${SERVICE_ACCOUNT_EMAIL}" \
      --set-secrets "${SECRET_MANAGER_BINDINGS}" \
      --set-env-vars "NODE_ENV=production"
  else
    gcloud run deploy "${SERVICE_NAME}" \
      --project "${PROJECT_ID}" \
      --image "${IMAGE}" \
      --platform managed \
      --region "${r}" \
      --allow-unauthenticated \
      --port 3000 \
      --set-env-vars "NODE_ENV=production"
  fi
}

for r in ${REGIONS}; do
  deploy_one "${r}"
done

echo "Done. Get URLs with:"
echo "  gcloud run services list --project ${PROJECT_ID} --platform managed"
