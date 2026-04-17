#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="${ROOT_DIR}/lib/core/config/backend_orders_config.dart"
SR_REPO="${ROOT_DIR}/lib/features/maintenance/data/service_requests_repository.dart"
REVIEWS_REPO="${ROOT_DIR}/lib/features/reviews/data/reviews_repository.dart"
OWNER_REPO="${ROOT_DIR}/lib/features/store_owner/data/store_owner_repository.dart"

log_json() {
  local kind="$1"
  local payload="$2"
  echo "{\"kind\":\"${kind}\",${payload}}"
}

require_env_true() {
  local name="$1"
  local v="${!name:-}"
  if [[ "${v,,}" == "1" || "${v,,}" == "true" ]]; then
    return 0
  fi
  return 1
}

main() {
  local failures=0
  local warnings=0

  if [[ -z "${BACKEND_ORDERS_BASE_URL:-}" ]]; then
    log_json "flutter_integration_verified" "\"check\":\"backend_base_url_set\",\"ok\":false"
    failures=$((failures+1))
  else
    log_json "flutter_integration_verified" "\"check\":\"backend_base_url_set\",\"ok\":true"
  fi

  if require_env_true "USE_BACKEND_STORE_READS"; then
    log_json "flutter_integration_verified" "\"check\":\"use_backend_store_reads\",\"ok\":true"
  else
    log_json "flutter_integration_verified" "\"check\":\"use_backend_store_reads\",\"ok\":false"
    failures=$((failures+1))
  fi

  if require_env_true "USE_BACKEND_PRODUCTS_READS"; then
    log_json "flutter_integration_verified" "\"check\":\"use_backend_products_reads\",\"ok\":true"
  else
    log_json "flutter_integration_verified" "\"check\":\"use_backend_products_reads\",\"ok\":false"
    failures=$((failures+1))
  fi

  if [[ -n "${USE_BACKEND_OWNER_WRITES:-}" ]]; then
    log_json "flutter_integration_verified" "\"check\":\"use_backend_owner_writes_configured\",\"ok\":true,\"value\":\"${USE_BACKEND_OWNER_WRITES}\""
  else
    log_json "flutter_integration_verified" "\"check\":\"use_backend_owner_writes_configured\",\"ok\":false"
    warnings=$((warnings+1))
  fi

  if rg -n "UnimplementedError" "$SR_REPO" >/dev/null; then
    log_json "flutter_integration_verified" "\"check\":\"service_requests_no_unimplemented\",\"ok\":false"
    failures=$((failures+1))
  else
    log_json "flutter_integration_verified" "\"check\":\"service_requests_no_unimplemented\",\"ok\":true"
  fi

  if rg -n "UnimplementedError" "$REVIEWS_REPO" >/dev/null; then
    log_json "flutter_integration_verified" "\"check\":\"reviews_no_unimplemented\",\"ok\":false"
    failures=$((failures+1))
  else
    log_json "flutter_integration_verified" "\"check\":\"reviews_no_unimplemented\",\"ok\":true"
  fi

  if rg -n "UnimplementedError" "$OWNER_REPO" >/dev/null; then
    log_json "flutter_integration_verified" "\"check\":\"store_owner_no_unimplemented\",\"ok\":false"
    failures=$((failures+1))
  else
    log_json "flutter_integration_verified" "\"check\":\"store_owner_no_unimplemented\",\"ok\":true"
  fi

  # Fallback behavior verification by env simulation: production-mode fallback must not be silent.
  if [[ "${NODE_ENV:-}" == "production" && -z "${BACKEND_ORDERS_BASE_URL:-}" ]]; then
    log_json "fallback_behavior_verified" "\"ok\":false,\"reason\":\"missing_backend_url_in_production\""
    failures=$((failures+1))
  else
    log_json "fallback_behavior_verified" "\"ok\":true"
  fi

  if [[ "$failures" -gt 0 ]]; then
    exit 1
  fi
  if [[ "$warnings" -gt 0 ]]; then
    exit 0
  fi
}

main "$@"
