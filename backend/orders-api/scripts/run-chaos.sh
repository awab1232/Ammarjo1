#!/usr/bin/env bash
# Start orders-api with Event Outbox chaos enabled (development/staging by default).
# Chaos is OFF unless EVENT_OUTBOX_CHAOS=1 — this script sets it to 1 unless already set.
#
# Production: requires EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION=1 or the chaos engine will not activate.
#
# Usage:
#   ./scripts/run-chaos.sh
#   ./scripts/run-chaos.sh --region-kill
#   ./scripts/run-chaos.sh --worker-crash 0.2 --db-latency 80
#   EVENT_OUTBOX_CHAOS_RUN_ID=my-run ./scripts/run-chaos.sh --replica-partition
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

export EVENT_OUTBOX_CHAOS="${EVENT_OUTBOX_CHAOS:-1}"
export EVENT_OUTBOX_CHAOS_RUN_ID="${EVENT_OUTBOX_CHAOS_RUN_ID:-chaos-$(date +%Y%m%d-%H%M%S)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region-kill)
      export EVENT_OUTBOX_CHAOS_REGION_KILL=1
      shift
      ;;
    --replica-partition)
      export EVENT_OUTBOX_CHAOS_REPLICA_PARTITION=1
      shift
      ;;
    --worker-crash)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --worker-crash <0-1>" >&2; exit 1; }
      export EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY="$2"
      shift 2
      ;;
    --db-latency)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --db-latency <ms>" >&2; exit 1; }
      export EVENT_OUTBOX_CHAOS_DB_LATENCY_MS="$2"
      shift 2
      ;;
    --replica-latency)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --replica-latency <ms>" >&2; exit 1; }
      export EVENT_OUTBOX_CHAOS_REPLICA_PARTITION_LATENCY_MS="$2"
      shift 2
      ;;
    --dlq-spike-min)
      [[ $# -ge 2 ]] || { echo "Usage: $0 --dlq-spike-min <n>" >&2; exit 1; }
      export EVENT_OUTBOX_CHAOS_DLQ_SPIKE_MIN="$2"
      shift 2
      ;;
    --allow-production)
      export EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "  --region-kill              EVENT_OUTBOX_CHAOS_REGION_KILL=1"
      echo "  --replica-partition        EVENT_OUTBOX_CHAOS_REPLICA_PARTITION=1"
      echo "  --worker-crash <0-1>       EVENT_OUTBOX_CHAOS_WORKER_CRASH_PROBABILITY"
      echo "  --db-latency <ms>          EVENT_OUTBOX_CHAOS_DB_LATENCY_MS"
      echo "  --replica-latency <ms>     EVENT_OUTBOX_CHAOS_REPLICA_PARTITION_LATENCY_MS"
      echo "  --dlq-spike-min <n>        EVENT_OUTBOX_CHAOS_DLQ_SPIKE_MIN"
      echo "  --allow-production         EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION=1 (NODE_ENV=production)"
      echo "Env: EVENT_OUTBOX_CHAOS, EVENT_OUTBOX_CHAOS_RUN_ID, NODE_ENV, etc. can be set before calling."
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

echo "Chaos run: EVENT_OUTBOX_CHAOS=${EVENT_OUTBOX_CHAOS} RUN_ID=${EVENT_OUTBOX_CHAOS_RUN_ID}"
if [[ "${NODE_ENV:-development}" == "production" ]] && [[ "${EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION:-}" != "1" ]]; then
  echo "WARN: NODE_ENV=production but EVENT_OUTBOX_CHAOS_ALLOW_PRODUCTION is not 1 — chaos engine will stay OFF." >&2
fi

exec npm run start:prod
