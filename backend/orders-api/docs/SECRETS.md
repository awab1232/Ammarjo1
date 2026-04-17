# Secrets & security — orders-api (Google Cloud Secret Manager)

This document describes **which values to store as secrets**, how to wire them to **Cloud Run** (optional, flag-based), and **operational security** practices. **No secrets belong in git** — use `.env` locally (gitignored) and Secret Manager in GCP.

The application **does not** embed the Google Cloud client library for Secret Manager at runtime; Cloud Run injects values as **environment variables** from mounted secrets.

---

## Secret inventory

| Variable / secret name | Criticality | Purpose |
|------------------------|-------------|---------|
| `DATABASE_URL` or `ORDERS_DATABASE_URL` | **Critical** (production) | PostgreSQL connection for orders, outbox, catalog (single-URL setups). |
| `ORDERS_DATABASE_URL_JO` / `ORDERS_DATABASE_URL_EG` (or `DATABASE_URL_JO` / `DATABASE_URL_EG`) | **Optional** | Multi-region Postgres URLs when `ENABLE_MULTI_REGION=1`. |
| `DATABASE_READ_REPLICA_URL` / per-region replica vars | **Optional** | Read replicas when DB read routing is enabled. |
| `REDIS_URL` | **Optional** (recommended if Redis features on) | Cache, rate limits, distributed locks when `REDIS_ENABLED=1`. |
| `ALGOLIA_APP_ID` | **Optional** | Product search — required for Algolia-backed search. |
| `ALGOLIA_SEARCH_API_KEY` | **Optional** | Server-side search with search-only key. |
| `ALGOLIA_WRITE_API_KEY` / `ALGOLIA_ADMIN_API_KEY` | **Optional** | Index sync / admin operations. |
| `ALGOLIA_PRODUCTS_INDEX` (and related index names) | **Optional** | Non-secret index names; can remain env vars. |
| `SEARCH_INTERNAL_API_KEY` | **Critical** (production) | Protects internal routes (`x-internal-api-key`), including `GET /internal/ops/global-health`. |
| `EVENT_ALERT_WEBHOOK_URL` | **Optional** | Generic webhook for outbox alerting when `EVENT_ALERT_ENABLED` is on. |
| `EVENT_ALERT_SLACK_WEBHOOK` | **Optional** | Slack webhook for alerts. |
| `EVENT_ALERT_EMAIL_URL` | **Optional** | Email/HTTP endpoint for alerts. |
| Firebase / GCP | **Optional** | `GOOGLE_APPLICATION_CREDENTIALS` locally; on Cloud Run use **metadata / workload identity** where applicable. |
| `GEMINI_*` / other AI keys | **Optional** | If any feature reads these env vars — treat as secrets. |

**Critical** = production deployments should not run without a deliberate decision (either the value is set, or the feature is intentionally off). **Optional** = feature degrades gracefully when unset.

---

## Rotation strategy (manual, current phase)

1. **Create a new Secret Manager version** with the new value (`gcloud secrets versions add ...` or `scripts/setup-secrets.sh` with updated env).
2. **Redeploy Cloud Run** (or wait for next revision) so new revisions pick up `:latest` or a pinned version.
3. **Invalidate old credentials** at the provider (Postgres password rotation, Algolia key rotation, etc.).
4. **Document** who rotated what and when (ticket / runbook).

Automated rotation (scheduler + IAM) can be added later.

---

## Cloud Run service account & IAM

The runtime identity that reads secrets must have **`secretmanager.secretAccessor`** on each secret (or on a project-level binding — prefer **least privilege** per secret).

### 1. Create a dedicated service account

```bash
gcloud iam service-accounts create orders-api-sa \
  --display-name="orders-api Cloud Run"
```

### 2. Grant Secret Accessor

For each secret ID (example names match env vars):

```bash
PROJECT_ID="your-project-id"
SA="orders-api-sa@${PROJECT_ID}.iam.gserviceaccount.com"

for SEC in DATABASE_URL REDIS_URL SEARCH_INTERNAL_API_KEY ALGOLIA_APP_ID ALGOLIA_SEARCH_API_KEY ALGOLIA_WRITE_API_KEY; do
  gcloud secrets add-iam-policy-binding "${SEC}" \
    --member="serviceAccount:${SA}" \
    --role="roles/secretmanager.secretAccessor"
done
```

Adjust the list to the secrets you actually create.

### 3. Assign to Cloud Run

Deploy with:

```bash
gcloud run deploy orders-api \
  --service-account="${SA}" \
  ...
```

Or use `scripts/deploy.sh` with `USE_SECRET_MANAGER=1` (see script header) which sets `--service-account` when using `--set-secrets`.

---

## Optional: Secret Manager via deploy script

Set `USE_SECRET_MANAGER=1` when running `scripts/deploy.sh` to mount secrets as env vars (see deploy script for exact `--set-secrets` list). If unset, behavior is unchanged: only `NODE_ENV=production` is set by the script; you add other env vars in the console or CI.

**Every secret ID listed in `SECRET_MANAGER_BINDINGS` must already exist** in Secret Manager or `gcloud run deploy` fails. Trim the list (or override `SECRET_MANAGER_BINDINGS`) if you omit optional secrets such as `REDIS_URL` or Algolia keys.

---

## Local development

- Use a **local `.env`** or shell exports — **never commit** `.env`.
- The app does **not** require Secret Manager locally.
- `env.validation.ts` may **warn** in production if recommended variables are missing; it does **not** exit the process.

---

## Best practices

- **Never commit** `.env`, JSON key files, or connection strings.
- **Separate secrets per environment** (staging vs production) — separate GCP projects or separate secret names/prefixes.
- **Rotate keys** on a schedule and after incidents.
- **Restrict IAM**: only CI deploy principals and the Cloud Run SA need `secretAccessor` on production secrets.
- **Audit**: enable Cloud Audit Logs for Secret Manager and IAM changes.
- **Logs**: do not log raw tokens, `Authorization` headers, or full database URLs (see code comments in pool initialization paths).

---

## Alert integration (event outbox)

Outbound alerts are **opt-in** and **non-blocking** (`EventOutboxAlertService`). Disable delivery with **`EVENT_ALERT_ENABLED=0`** (default is enabled when unset — set `0` to turn off outbound posts).

### Environment variables

| Variable | Role |
|----------|------|
| `EVENT_ALERT_ENABLED` | Set to **`0`** to disable webhook/Slack/email delivery (in-process alert history may still update in some paths). |
| `EVENT_ALERT_WEBHOOK_URL` | **HTTPS POST** — JSON body (generic automation, PagerDuty-compatible adapters, etc.). |
| `EVENT_ALERT_SLACK_WEBHOOK` | Slack **Incoming Webhook** URL (`https://hooks.slack.com/services/...`). |
| `EVENT_ALERT_EMAIL_URL` | Optional third HTTP endpoint receiving the **same JSON** as the generic webhook (e.g. email provider HTTP API). |

Tune thresholds with **`EVENT_ALERT_FAILURE_THRESHOLD`**, **`EVENT_ALERT_WINDOW_MS`**, **`EVENT_ALERT_RETRY_EXPLOSION_*`**, **`EVENT_ALERT_STUCK_*`**, **`EVENT_ALERT_DEAD_LETTER_DELTA`**, **`EVENT_ALERT_MIN_INTERVAL_MS`** (see `event-outbox-alert-config.ts`).

### Slack webhook setup

1. In Slack: **Apps** → **Incoming Webhooks** → add to channel → copy URL.
2. Set **`EVENT_ALERT_SLACK_WEBHOOK`** to that URL (Secret Manager in production).
3. Deploy; worker ticks and DLQ events may POST to Slack.

Slack receives **`{ "text": "<message>" }`** — plain text (not the full JSON payload).

### Generic webhook JSON payload

`EVENT_ALERT_WEBHOOK_URL` and `EVENT_ALERT_EMAIL_URL` receive **`application/json`**:

```json
{
  "source": "orders-api-event-outbox",
  "severity": "warning",
  "title": "Event outbox alert",
  "message": "High dead-letter rate: …",
  "details": { },
  "ts": "2026-01-15T12:00:00.000Z"
}
```

`details` may include **`metrics`**, **`tick`**, **`eventIds`**, **`requeued`**, etc., depending on alert kind.

### Expected alert kinds (history / dedupe keys)

| Kind | When |
|------|------|
| `periodic` | Sliding-window checks: high dead-letter rate, retry pressure, dead-letter growth, worker stuck. |
| `dead_letter` | Event(s) moved to terminal **failed** status. |
| `manual_retry_one` | `POST /internal/events/retry/:eventId` |
| `manual_retry_all` | `POST /internal/events/retry-all-failed` |

**Deduping**: same key is rate-limited by **`EVENT_ALERT_MIN_INTERVAL_MS`** (default 120s).

### Verify connectivity

Use **`scripts/test-alerts.sh`** (reads `summary` / `alerts-history`; optional safe `retry` probe). Real DLQ spikes require failing handlers or chaos — see `CHAOS_TESTING.md`.

---

## Related docs

- `docs/SLO.md` — service level objectives and endpoint mapping.
- `docs/MONITORING.md` — metrics and anomaly interpretation.
- `docs/RUNBOOK.md` — incidents (DB, DLQ, latency, regions).
- `docs/CHAOS_TESTING.md` — chaos / failover validation; uses `SEARCH_INTERNAL_API_KEY` for dashboard exports.
- `docs/CLOUD_RUN.md` — container, health, regions.
- `docs/GLOBAL_ROUTING.md` — load balancer (optional).
- `scripts/setup-secrets.sh` — create/update secrets from environment variables (bash).
- `scripts/setup-secrets-algolia.ps1` — same flow for Algolia keys only (**Windows PowerShell**); set `ALGOLIA_APP_ID`, `ALGOLIA_SEARCH_API_KEY`, `ALGOLIA_WRITE_API_KEY` env vars, then run the script.
- `scripts/deploy.sh` — optional `USE_SECRET_MANAGER=1`.
