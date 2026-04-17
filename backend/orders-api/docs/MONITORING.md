# Monitoring guide — orders-api

This document explains **public and internal endpoints** for operations and how to interpret **anomalies**. No code changes are required — use your existing **`SEARCH_INTERNAL_API_KEY`** for internal routes.

---

## Public endpoints

### `GET /health`

| Field | Meaning |
|-------|---------|
| `ok` | Process is running and responding. |
| `service` | Always `orders-api` for this service. |
| `postgresql.configured` | Whether a database URL was wired at startup. |
| `postgresql.ok` | Last ping success when configured; `null` if not configured. |

**Anomalies**

- `ok: true` but `postgresql.ok: false` → DB unreachable or misconfigured; see `RUNBOOK.md` (DB).
- Always use this path for **load balancer** and **Kubernetes/Cloud Run** probes (no auth).

---

## Internal endpoints (require `x-internal-api-key`)

### `GET /internal/ops/global-health`

Aggregated snapshot: **region routing**, **Redis**, **database** primary/replica ping, **outbox** backlog + lag by region, **cache** hit ratio (when telemetry enabled).

**Anomalies**

- `database.primary.ok: false` → connectivity or credentials.
- `outbox.backlogEligibleApprox` very high vs baseline → worker lag or overload.
- `outbox.lagByRegion` — uneven **eligible_pending** / **processing** by region → multi-region or worker imbalance.
- `redis.ready: false` when you expect cache/rate limits → check `REDIS_URL` and network.

---

### `GET /internal/ops/dashboard/summary?hours=24`

| Area | Meaning |
|------|---------|
| `metrics.emitted` | Events inserted into outbox in the window. |
| `metrics.processed` | Terminal `processed` count in the window. |
| `metrics.failedInWindow` | Terminal `failed` in the window (DLQ-related). |
| `metrics.dlqCount` | Total terminal failed rows (approximate snapshot semantics — see service). |
| `metrics.successFailureRatio` | `processed` vs `failedTerminal` ratio when applicable. |
| `metrics.retryDistribution` | Histogram of `retry_count` for in-flight / pending work. |
| `metrics.workerThroughput` | In-memory worker throughput estimate. |
| `alerts.active` | **Active alert conditions** (threshold breaches), same family as outbound webhooks. |
| `alerts.lastAlertAt` | Last time an alert was recorded in history. |

**Anomalies**

- `failedInWindow` jumps while `processed` flat → failures or poison messages.
- `retryDistribution` skewed to high retries → **retry explosion** risk (alerts may fire).
- `alerts.activeCount` &gt; 0 → open `alerts-history` and correlate with `EVENT_ALERT_*` thresholds.

---

### `GET /internal/ops/dashboard/events-timeline?hours=48`

Hourly (or bucketed) series: **emitted**, **processing**, **processed**, **failed**.

**Anomalies**

- **failed** bucket spikes without matching **processed** recovery → investigate handlers and DLQ.
- **processing** stuck high → workers not completing (stuck rows, DB locks).

---

### `GET /internal/ops/dashboard/alerts-history?limit=100`

In-memory **ring buffer** of dispatched alerts (`kind`, `message`, `details`, `ts`).

**Anomalies**

- Burst of `dead_letter` or `periodic` → align with worker logs and DB.

---

### `GET /internal/ops/dashboard/chaos-report`

Chaos / resilience snapshot when **`EVENT_OUTBOX_CHAOS=1`**; when chaos is off, `chaosActive` is false. Use for **chaos test runs** only — see `CHAOS_TESTING.md`.

---

## Interpreting anomalies (quick reference)

| Symptom | Check first |
|---------|-------------|
| HTTP errors spike | Cloud Run / LB 5xx; then `global-health` DB/Redis. |
| Slow API | Provider latency metrics; DB pool; Redis. |
| Outbox backlog | `summary` + `global-health.outbox`; worker scaling; `events-timeline` failed series. |
| Alerts firing | `alerts-history`, `SECRETS.md` webhook URLs, `event-outbox-alert-config` env tuning. |

---

## Optional integrations (no code in repo)

| Tool | Approach |
|------|----------|
| **Google Cloud Monitoring** | Dashboards on Cloud Run metrics; uptime checks on `/health`; log-based metrics. |
| **Grafana** | Stackdriver / GCP datasource, or **Mimir**/**Prometheus** with exported metrics (future). |
| **Prometheus** | Not native; add **OpenTelemetry** or **prometheus exporter** in a future change, or scrape **pushgateway** from a side job. |

---

## Related docs

- `docs/SLO.md` — targets and how endpoints map to them.
- `docs/RUNBOOK.md` — incident steps.
- `docs/SECRETS.md` — internal API key and alert webhooks.
- `docs/CHAOS_TESTING.md` — chaos report and load testing.
