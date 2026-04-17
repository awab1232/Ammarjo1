#!/usr/bin/env bash
# Global external HTTPS load balancer: URL map → backend service → serverless NEGs (from setup-neg.sh).
# Creates optional Google-managed SSL cert, target HTTPS proxy, forwarding rule on :443.
#
# Run AFTER: scripts/setup-neg.sh
#
# Usage:
#   export GCP_PROJECT_ID=my-project
#   export MANAGED_SSL_DOMAIN=api.example.com   # optional; Google-managed cert
#   # OR use an existing cert:
#   # export SSL_CERT_NAME=my-existing-cert
#   ./scripts/setup-global-lb-https.sh
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

BACKEND_SERVICE="${BACKEND_SERVICE:-orders-api-backend}"
URL_MAP="${URL_MAP:-orders-api-map}"
HTTPS_PROXY="${HTTPS_PROXY:-orders-api-proxy}"
FORWARDING_RULE="${FORWARDING_RULE:-orders-api-https}"
ADDRESS_NAME="${ADDRESS_NAME:-orders-api-lb-ip}"

# SSL: prefer explicit cert name; else create/use Google-managed cert for MANAGED_SSL_DOMAIN
SSL_CERT_NAME="${SSL_CERT_NAME:-}"

gcloud config set project "${PROJECT_ID}" >/dev/null

if ! gcloud compute backend-services describe "${BACKEND_SERVICE}" --global &>/dev/null; then
  echo "Backend service '${BACKEND_SERVICE}' not found. Run scripts/setup-neg.sh first." >&2
  exit 1
fi

if gcloud compute addresses describe "${ADDRESS_NAME}" --global &>/dev/null; then
  echo "Global address exists: ${ADDRESS_NAME}"
else
  echo "Creating global static IP: ${ADDRESS_NAME}"
  gcloud compute addresses create "${ADDRESS_NAME}" --global
fi

LB_IP="$(gcloud compute addresses describe "${ADDRESS_NAME}" --global --format='value(address)')"
echo "Load balancer IP: ${LB_IP}"

if [[ -z "${SSL_CERT_NAME}" ]]; then
  if [[ -n "${MANAGED_SSL_DOMAIN:-}" ]]; then
    SSL_CERT_NAME="orders-api-managed-cert"
    if gcloud compute ssl-certificates describe "${SSL_CERT_NAME}" --global &>/dev/null; then
      echo "SSL certificate exists: ${SSL_CERT_NAME}"
    else
      echo "Creating Google-managed certificate for ${MANAGED_SSL_DOMAIN}"
      gcloud compute ssl-certificates create "${SSL_CERT_NAME}" \
        --domains="${MANAGED_SSL_DOMAIN}" \
        --global
    fi
  else
    echo "Set MANAGED_SSL_DOMAIN (for auto-managed cert) or SSL_CERT_NAME (existing global cert)." >&2
    echo "Example: export MANAGED_SSL_DOMAIN=api.example.com" >&2
    exit 1
  fi
else
  if ! gcloud compute ssl-certificates describe "${SSL_CERT_NAME}" --global &>/dev/null; then
    echo "SSL certificate not found: ${SSL_CERT_NAME}" >&2
    exit 1
  fi
fi

if gcloud compute url-maps describe "${URL_MAP}" --global &>/dev/null; then
  echo "URL map exists: ${URL_MAP}"
else
  echo "Creating URL map ${URL_MAP}"
  gcloud compute url-maps create "${URL_MAP}" \
    --default-service="${BACKEND_SERVICE}"
fi

if gcloud compute target-https-proxies describe "${HTTPS_PROXY}" --global &>/dev/null; then
  echo "HTTPS proxy exists: ${HTTPS_PROXY}"
else
  echo "Creating target HTTPS proxy ${HTTPS_PROXY}"
  gcloud compute target-https-proxies create "${HTTPS_PROXY}" \
    --url-map="${URL_MAP}" \
    --ssl-certificates="${SSL_CERT_NAME}"
fi

if gcloud compute forwarding-rules describe "${FORWARDING_RULE}" --global &>/dev/null; then
  echo "Forwarding rule exists: ${FORWARDING_RULE}"
else
  echo "Creating global forwarding rule ${FORWARDING_RULE} (HTTPS :443)"
  gcloud compute forwarding-rules create "${FORWARDING_RULE}" \
    --global \
    --target-https-proxy="${HTTPS_PROXY}" \
    --address="${ADDRESS_NAME}" \
    --ports=443
fi

echo ""
echo "Done."
echo "  DNS: point your hostname (e.g. api.example.com) A/AAAA record to: ${LB_IP}"
echo "  HTTPS cert '${SSL_CERT_NAME}' must become ACTIVE (DNS must hit this IP first for Google-managed certs)."
echo "  Test: curl -sS https://YOUR_DOMAIN/health"
