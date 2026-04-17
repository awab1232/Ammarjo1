# Service Level Objectives (SLOs) — orders-api

SLOs are **targets** for production reliability. This service does not enforce SLOs in code; you measure them with **uptime probes**, **APM / load balancer logs**, and the **internal ops JSON** endpoints below.

---

## Availability

| Target | **99.9%** monthly (≈ 43 minutes acceptable downtime) |
|--------|----------------------------------------------------------|

**How to measure**

- **Synthetic / LB**: Success rate of `GET /health` (or TCP health checks) from your global load balancer or Cloud Monitoring uptime checks. `GET /health` returns `ok: true` when the process is up; `postgresql.configured` reflects DB wiring, not GCP uptime of the whole stack.
- **Process**: Cloud Run / GKE **instance availability** and **cold start** rates (provider metrics).

**Gap**: Pure API SLO needs **external** probing (not only in-app JSON).

---

## Latency

| Target | **p95 API latency &lt; 500 ms** (excluding intentionally slow routes) |
|--------|-------------------------------------------------------------------------|

**How to measure**

- **Google Cloud Monitoring** (or similar): p50/p95/p99 on Cloud Run request latency, or HTTP(S) LB backend latency.
- **APM** (Datadog, New Relic, etc.): instrument Nest if you add middleware later.
- The **orders-api** handlers do not expose a built-in latency histogram JSON; use **infrastructure metrics**.

**Anomaly**: p95 &gt; 500 ms sustained → see `RUNBOOK.md` (latency).

---

## Error rate

| Target | **HTTP 5xx rate &lt; 1%** of requests (excluding health checks if you filter them) |
|--------|-------------------------------------------------------------------------------------|

**How to measure**

- Cloud Run / LB **request count by status class** (2xx vs 5xx).
- Optional: correlate with **application logs** for `500` responses.

**Related app signal**: `GET /internal/ops/dashboard/summary` → `metrics.successFailureRatio` for **event outbox terminal outcomes** (processed vs failed), not HTTP — see “Event processing” below.

---

## Event processing (outbox)

| Metric | Target | How to measure (existing) |
|--------|--------|---------------------------|
| **Outbox success rate** | **&gt; 99%** of terminal outcomes | `GET /internal/ops/dashboard/summary?hours=24` → `metrics.successFailureRatio.rate` (processed / (processed + failedTerminal)) when `terminal > 0`. |
| **DLQ rate** | **&lt; 0.1%** of events (interpretation) | Same window: `metrics.dlqCount` vs `metrics.emitted` over the window is a **coarse** ratio; precise DLQ share requires SQL or extended metrics. Use `dlqCount` trend + `events-timeline` **failed** buckets. |

**Notes**

- `summary` is **cached** briefly (`cacheTtlMs`); acceptable for SLO dashboards.
- “Success” here means **processed** vs **terminal failed** (DLQ), not HTTP delivery to webhooks.

---

## Recovery (DLQ replay)

| Target | **Manual / automatic replay success &gt; 95%** (operational) |
|--------|--------------------------------------------------------------|

**How to measure**

- After `POST /internal/events/retry-all-failed` or `POST /internal/events/retry/:eventId`, compare **dashboard** counts (`GET /internal/events/dashboard`) before/after: failed count should drop when events re-enter `pending` and eventually `processed`.
- Track **ops** retries via `GET /internal/ops/dashboard/alerts-history` entries `manual_retry_one`, `manual_retry_all`.

**Gap**: No single numeric “replay success %” in JSON — derive from **dashboard stats** + **timeline** over time.

---

## Dashboard usage for SLO review

| Endpoint | Role |
|----------|------|
| `GET /health` | Liveness; availability probe. |
| `GET /internal/ops/global-health` | DB, Redis, outbox **lag by region**, cache — holistic health. |
| `GET /internal/ops/dashboard/summary` | Outbox KPIs, **successFailureRatio**, **dlqCount**, alerts. |
| `GET /internal/ops/dashboard/events-timeline` | Time-bucketed **failed** vs processed — trend validation. |
| `GET /internal/ops/dashboard/chaos-report` | Only during chaos runs; omit from production SLO dashboards normally. |

All `/internal/*` routes require **`SEARCH_INTERNAL_API_KEY`** + header `x-internal-api-key` (see `SECRETS.md`).

---

## Optional: external observability

- **Google Cloud Monitoring**: dashboards on Cloud Run request count, latency, errors; optional **log-based metrics** from structured logs.
- **Grafana / Prometheus**: export metrics from GCP or add a **metrics sidecar** later; not built into orders-api today.

See `MONITORING.md` for interpretation and `RUNBOOK.md` for incidents.
