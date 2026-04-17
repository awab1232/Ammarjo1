# Global SaaS Architecture

## Regional model

- Regions currently modeled: **JO (Jordan)** and **EG (Egypt)**.
- Fallback path exists when no explicit region/country is supplied.
- Request hints are accepted via headers:
  - `x-region`
  - `x-country` (through country normalization flow)

## Routing strategy

- `DataRoutingService` resolves:
  - write DB target (`primary_pg_jo`, `primary_pg_eg`, fallback `primary`)
  - read replica target (`replica_jo`, `replica_eg`, fallback `primary`)
  - cache namespace (`cache:jo:` / `cache:eg:`)
  - event outbox region tag (`jo` / `eg`)
- Strategy layer (`MultiRegionStrategyService`) can override read/write routing for failover.

## Database split strategy

- Primary pools are region-aware when multi-region routing is enabled.
- Read paths prefer regional replicas and safely fall back to primary.
- Global health endpoint reports primary/replica status and replica lag when available.

## Cache strategy

- Cache keys are namespaced by region through routing.
- Rate-limit keys are namespaced to prevent cross-environment collisions.
- Cache hit ratio and Redis ops are exposed in global health.

## Event outbox regional isolation

- Outbox rows carry optional `region` + `processing_region`.
- Workers claim using `FOR UPDATE SKIP LOCKED` with regional filtering.
- Missing-region events remain processable through fallback logic.
- Foreign-region stale recovery supports disaster failover.

## Future Kubernetes scale path

- Deploy one workload per region with region-local DB + Redis endpoints.
- Keep outbox workers active per region; use kill/degraded toggles for controlled failover.
- Route traffic by geo at edge/load balancer, then enforce regional data routing in-app.
- Extend region set (`SA`, `AE`, etc.) by adding country normalization + routing keys and pools.

