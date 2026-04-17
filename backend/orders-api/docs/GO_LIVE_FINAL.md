# Final Go-Live Gate

## 1) Database readiness

- Primary DB health check is green.
- Read replica health is green (or intentionally disabled with documented reason).
- Replica lag is below threshold.
- Required indexes are applied (`service_requests`, `ratings_reviews`, `wholesale_orders`, `event_outbox`).

## 2) Redis readiness

- Redis connectivity is healthy when enabled.
- Cache namespace and rate-limit key namespaces are configured.
- TTL behavior is verified (no unbounded growth patterns).

## 3) Event outbox stability

- Worker is processing normally (no kill switch/degraded mode in production unless incident response).
- Backlog and processing pressure are below alert thresholds.
- Retry behavior remains stable under load.

## 4) DLQ threshold check

- Terminal failed rows are within acceptable limits.
- DLQ pruning/retention settings are configured and tested.
- Alerting channel is reachable for DLQ growth warnings.

## 5) SLO compliance

- Error rate and latency targets meet `docs/SLO.md`.
- Outbox lag and DLQ warning thresholds are configured.
- Global health reports no critical readiness warnings.

## 6) Load test validation

- Run:
  - `scripts/load-test-orders.sh`
  - `scripts/load-test-service-requests.sh`
  - `scripts/load-test-wholesale.sh`
- Validate request latency trends and endpoint behavior across 50-500 sequential requests.
- In mock mode, confirm no business data mutation.

## 7) Region routing validation

- Verify JO/EG/fallback resolution in routing layer.
- Confirm cache namespace separation by region.
- Confirm outbox region tagging and region-safe processing/fallback.

## Final decision gate

- `GET /internal/ops/global-health` must show:
  - `isProductionReady = true`
  - `criticalWarnings = []`
  - `systemScore >= 90`

