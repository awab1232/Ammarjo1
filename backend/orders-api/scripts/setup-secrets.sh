#!/usr/bin/env bash
# Create or update Google Secret Manager secrets from environment variables (additive, idempotent create).
# Does NOT print secret values. Requires: gcloud auth, secretmanager.googleapis.com enabled.
#
# Usage (set values in the shell, then run):
#   export GCP_PROJECT_ID=my-project
#   export DATABASE_URL='postgresql://...'
#   export REDIS_URL='redis://...'
#   export SEARCH_INTERNAL_API_KEY='...'
#   export ALGOLIA_APP_ID='...'
#   export ALGOLIA_SEARCH_API_KEY='...'
#   export ALGOLIA_WRITE_API_KEY='...'
#   ./scripts/setup-secrets.sh
#
# To add a new version for an existing secret without recreating:
#   export DATABASE_URL='new-value'
#   ./scripts/setup-secrets.sh   # only processes vars that are set
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

gcloud config set project "${PROJECT_ID}" >/dev/null

ensure_secret_exists() {
  local name="$1"
  if gcloud secrets describe "${name}" --project="${PROJECT_ID}" &>/dev/null; then
    return 0
  fi
  echo "Creating secret: ${name}"
  gcloud secrets create "${name}" \
    --project="${PROJECT_ID}" \
    --replication-policy="automatic"
}

add_version_from_value() {
  local name="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  # NUL-safe: write exact bytes (no trailing newline required for URLs/keys)
  printf '%s' "${value}" > "${tmp}"
  gcloud secrets versions add "${name}" \
    --project="${PROJECT_ID}" \
    --data-file="${tmp}"
  rm -f "${tmp}"
  echo "Added new version for: ${name}"
}

# name_in_gcp, env_var_name
process_secret() {
  local secret_id="$1"
  local env_name="$2"
  local val
  val="${!env_name:-}"
  if [[ -z "${val}" ]]; then
    echo "  (skip) ${secret_id} — ${env_name} not set"
    return 0
  fi
  ensure_secret_exists "${secret_id}"
  add_version_from_value "${secret_id}" "${val}"
}

echo "Project: ${PROJECT_ID}"
echo "Processing secrets from env (unset vars are skipped)..."

# Map: GCP secret resource ID = same as common env var name (adjust if you use hyphenated IDs)
process_secret "DATABASE_URL" "DATABASE_URL"
process_secret "REDIS_URL" "REDIS_URL"
process_secret "SEARCH_INTERNAL_API_KEY" "SEARCH_INTERNAL_API_KEY"
process_secret "ALGOLIA_APP_ID" "ALGOLIA_APP_ID"
process_secret "ALGOLIA_SEARCH_API_KEY" "ALGOLIA_SEARCH_API_KEY"
process_secret "ALGOLIA_WRITE_API_KEY" "ALGOLIA_WRITE_API_KEY"
process_secret "EVENT_ALERT_WEBHOOK_URL" "EVENT_ALERT_WEBHOOK_URL"

echo "Done. Bind secrets to Cloud Run with deploy.sh USE_SECRET_MANAGER=1 or gcloud --set-secrets."
