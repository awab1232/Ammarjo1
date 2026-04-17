#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
INTERNAL_API_KEY="${INTERNAL_API_KEY:-${SEARCH_INTERNAL_API_KEY:-}}"
CUSTOMER_TOKEN="${CUSTOMER_TOKEN:-}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
OTHER_TENANT_TOKEN="${OTHER_TENANT_TOKEN:-}"
REQUEST_ID="${REQUEST_ID:-}"

log_json() {
  local kind="$1"
  local payload="$2"
  echo "{\"kind\":\"${kind}\",${payload}}"
}

http_status() {
  local method="$1"
  local url="$2"
  local auth="${3:-}"
  local internal="${4:-}"
  if [[ -n "$auth" && -n "$internal" ]]; then
    curl -sS -o /tmp/smoke_body.txt -w "%{http_code}" -X "$method" \
      -H "Authorization: Bearer $auth" -H "x-internal-api-key: $internal" "$url"
  elif [[ -n "$auth" ]]; then
    curl -sS -o /tmp/smoke_body.txt -w "%{http_code}" -X "$method" \
      -H "Authorization: Bearer $auth" "$url"
  elif [[ -n "$internal" ]]; then
    curl -sS -o /tmp/smoke_body.txt -w "%{http_code}" -X "$method" \
      -H "x-internal-api-key: $internal" "$url"
  else
    curl -sS -o /tmp/smoke_body.txt -w "%{http_code}" -X "$method" "$url"
  fi
}

assert_status() {
  local name="$1"
  local got="$2"
  local expected="$3"
  if [[ "$got" != "$expected" ]]; then
    log_json "api_smoke_test_result" "\"name\":\"${name}\",\"ok\":false,\"expected\":\"${expected}\",\"got\":\"${got}\""
    return 1
  fi
  log_json "api_smoke_test_result" "\"name\":\"${name}\",\"ok\":true,\"status\":\"${got}\""
}

main() {
  local failures=0

  s=$(http_status "GET" "${BASE_URL}/stores")
  assert_status "stores_without_auth" "$s" "401" || failures=$((failures+1))

  s=$(http_status "GET" "${BASE_URL}/internal/metrics")
  assert_status "internal_metrics_without_internal_key" "$s" "401" || failures=$((failures+1))

  if [[ -n "$CUSTOMER_TOKEN" ]]; then
    s=$(http_status "GET" "${BASE_URL}/service-requests?customerId=me" "$CUSTOMER_TOKEN")
    if [[ "$s" == "200" || "$s" == "403" ]]; then
      log_json "api_smoke_test_result" "\"name\":\"service_requests_list_customer\",\"ok\":true,\"status\":\"${s}\""
    else
      log_json "api_smoke_test_result" "\"name\":\"service_requests_list_customer\",\"ok\":false,\"status\":\"${s}\""
      failures=$((failures+1))
    fi
  else
    log_json "api_smoke_test_result" "\"name\":\"service_requests_list_customer\",\"ok\":false,\"reason\":\"CUSTOMER_TOKEN missing\""
    failures=$((failures+1))
  fi

  if [[ -n "$REQUEST_ID" && -n "$CUSTOMER_TOKEN" ]]; then
    s=$(http_status "GET" "${BASE_URL}/service-requests/${REQUEST_ID}" "$CUSTOMER_TOKEN")
    if [[ "$s" == "200" || "$s" == "403" || "$s" == "404" ]]; then
      log_json "api_smoke_test_result" "\"name\":\"service_requests_get_by_id\",\"ok\":true,\"status\":\"${s}\""
    else
      log_json "api_smoke_test_result" "\"name\":\"service_requests_get_by_id\",\"ok\":false,\"status\":\"${s}\""
      failures=$((failures+1))
    fi
  fi

  if [[ -n "$REQUEST_ID" && -n "$CUSTOMER_TOKEN" ]]; then
    s=$(http_status "POST" "${BASE_URL}/service-requests/${REQUEST_ID}/start" "$CUSTOMER_TOKEN")
    if [[ "$s" == "403" || "$s" == "200" ]]; then
      log_json "api_smoke_test_result" "\"name\":\"service_requests_start\",\"ok\":true,\"status\":\"${s}\""
    else
      log_json "api_smoke_test_result" "\"name\":\"service_requests_start\",\"ok\":false,\"status\":\"${s}\""
      failures=$((failures+1))
    fi
  fi

  if [[ -n "$REQUEST_ID" && -n "$CUSTOMER_TOKEN" ]]; then
    s=$(http_status "POST" "${BASE_URL}/service-requests/${REQUEST_ID}/complete" "$CUSTOMER_TOKEN")
    if [[ "$s" == "403" || "$s" == "200" ]]; then
      log_json "api_smoke_test_result" "\"name\":\"service_requests_complete\",\"ok\":true,\"status\":\"${s}\""
    else
      log_json "api_smoke_test_result" "\"name\":\"service_requests_complete\",\"ok\":false,\"status\":\"${s}\""
      failures=$((failures+1))
    fi
  fi

  # RBAC check: customer should not access internal admin analytics.
  if [[ -n "$CUSTOMER_TOKEN" ]]; then
    s=$(http_status "GET" "${BASE_URL}/internal/analytics/overview" "$CUSTOMER_TOKEN")
    if [[ "$s" == "401" || "$s" == "403" ]]; then
      log_json "security_enforcement_verified" "\"check\":\"rbac_admin_endpoint_blocked_for_customer\",\"status\":\"${s}\""
    else
      log_json "security_enforcement_verified" "\"check\":\"rbac_admin_endpoint_blocked_for_customer\",\"status\":\"${s}\",\"ok\":false"
      failures=$((failures+1))
    fi
  fi

  # Tenant isolation check (requires a second tenant token and known request id not belonging to that tenant).
  if [[ -n "$OTHER_TENANT_TOKEN" && -n "$REQUEST_ID" ]]; then
    s=$(http_status "GET" "${BASE_URL}/service-requests/${REQUEST_ID}" "$OTHER_TENANT_TOKEN")
    if [[ "$s" == "403" || "$s" == "404" ]]; then
      log_json "security_enforcement_verified" "\"check\":\"tenant_isolation_cross_request\",\"status\":\"${s}\""
    else
      log_json "security_enforcement_verified" "\"check\":\"tenant_isolation_cross_request\",\"status\":\"${s}\",\"ok\":false"
      failures=$((failures+1))
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
