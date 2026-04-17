#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:3000}"
CUSTOMER_TOKEN="${CUSTOMER_TOKEN:-}"
TECHNICIAN_TOKEN="${TECHNICIAN_TOKEN:-}"
ADMIN_TOKEN="${ADMIN_TOKEN:-}"
TECHNICIAN_ID="${TECHNICIAN_ID:-}"

log_json() {
  local kind="$1"
  local payload="$2"
  echo "{\"kind\":\"${kind}\",${payload}}"
}

require_env() {
  local name="$1"
  local val="${!name:-}"
  if [[ -z "$val" ]]; then
    echo "Missing required env: $name" >&2
    exit 1
  fi
}

http_json() {
  local method="$1"
  local url="$2"
  local token="$3"
  local body="${4:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "$url" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -sS -X "$method" "$url" -H "Authorization: Bearer $token"
  fi
}

status_only() {
  local method="$1"
  local url="$2"
  local token="$3"
  local body="${4:-}"
  if [[ -n "$body" ]]; then
    curl -sS -o /tmp/e2e_body.txt -w "%{http_code}" -X "$method" "$url" \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -sS -o /tmp/e2e_body.txt -w "%{http_code}" -X "$method" "$url" \
      -H "Authorization: Bearer $token"
  fi
}

main() {
  require_env "CUSTOMER_TOKEN"
  require_env "TECHNICIAN_TOKEN"
  require_env "ADMIN_TOKEN"
  require_env "TECHNICIAN_ID"

  local conversation_id="e2e_conv_$(date +%s)"
  local create_body
  create_body=$(printf '{"conversationId":"%s","description":"E2E production verification flow"}' "$conversation_id")
  local create_resp
  create_resp=$(http_json "POST" "${BASE_URL}/service-requests" "$CUSTOMER_TOKEN" "$create_body")
  local request_id
  request_id=$(printf "%s" "$create_resp" | rg -o '"id"\s*:\s*"[^"]+"' -r '$0' | rg -o '[0-9a-fA-F-]{36}' || true)
  if [[ -z "$request_id" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"create_request\",\"response\":\"${create_resp//\"/\\\"}\""
    exit 1
  fi

  local assign_body
  assign_body=$(printf '{"technicianId":"%s"}' "$TECHNICIAN_ID")
  local st
  st=$(status_only "POST" "${BASE_URL}/service-requests/${request_id}/assign" "$ADMIN_TOKEN" "$assign_body")
  if [[ "$st" != "201" && "$st" != "200" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"assign\",\"status\":\"${st}\""
    exit 1
  fi

  st=$(status_only "GET" "${BASE_URL}/service-requests?technicianId=${TECHNICIAN_ID}" "$TECHNICIAN_TOKEN")
  if [[ "$st" != "200" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"technician_fetch\",\"status\":\"${st}\""
    exit 1
  fi

  st=$(status_only "POST" "${BASE_URL}/service-requests/${request_id}/start" "$TECHNICIAN_TOKEN" "{}")
  if [[ "$st" != "201" && "$st" != "200" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"technician_start\",\"status\":\"${st}\""
    exit 1
  fi

  st=$(status_only "POST" "${BASE_URL}/service-requests/${request_id}/complete" "$TECHNICIAN_TOKEN" "{}")
  if [[ "$st" != "201" && "$st" != "200" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"technician_complete\",\"status\":\"${st}\""
    exit 1
  fi

  st=$(status_only "GET" "${BASE_URL}/service-requests/${request_id}" "$ADMIN_TOKEN")
  if [[ "$st" != "200" ]]; then
    log_json "e2e_flow_verified" "\"ok\":false,\"stage\":\"admin_view\",\"status\":\"${st}\""
    exit 1
  fi

  log_json "e2e_flow_verified" "\"ok\":true,\"requestId\":\"${request_id}\",\"flow\":\"customer_create_technician_start_complete_admin_view\""
}

main "$@"
