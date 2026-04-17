# Global traffic routing — orders-api (Cloud Load Balancing + Cloud Run)

This document describes how to expose **one hostname** (e.g. `api.example.com`) in front of **regional Cloud Run** deployments, using **Google Cloud Load Balancing** with **Serverless Network Endpoint Groups (NEGs)**.

**Backend application code is unchanged** — routing is entirely at the edge (GCP).

---

## Target regions (product mapping)

| Market (example) | Cloud Run region | Notes |
|------------------|------------------|--------|
| Egypt (EG)       | `europe-west1`   | Deploy `orders-api` here; NEG attaches this service. |
| Jordan (JO)      | `me-central1`    | Deploy `orders-api` here; NEG attaches this service. |

These regions match your **multi-region Cloud Run** layout (`scripts/deploy.sh`). The load balancer **does not** automatically “pin Egypt to EU and Jordan to ME” with the basic setup below — see [Geo routing approach](#geo-routing-approach).

---

## Domain & DNS

1. **Choose a hostname** for the API, e.g. `api.yourdomain.com`.
2. **DNS**
   - **Cloud DNS** (recommended in GCP): create an **A** or **AAAA** record (or **CNAME** if your provider requires) pointing to the **global external IP** of the HTTPS forwarding rule (see scripts output).
   - **External DNS** (Cloudflare, Route53, etc.): same — point `api.yourdomain.com` to that **static global IP**.
3. **Propagation**: allow TTL; verify with `dig api.yourdomain.com`.

---

## SSL / TLS

- Google Cloud **HTTPS load balancers** require a **SSL certificate** resource attached to the **target HTTPS proxy**.
- **Recommended**: [Google-managed certificate](https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs) for your public domain (`api.yourdomain.com`).
- The certificate must be **ACTIVE** before HTTPS clients succeed; provisioning can take several minutes after DNS points to the LB IP.

---

## Architecture (high level)

```
Clients → Global external HTTPS LB → URL map → Backend service → Serverless NEGs → Cloud Run (per region)
```

- **Two NEGs** (one per region) reference the **same Cloud Run service name** (`orders-api`), each in its region.
- **One backend service** lists both NEGs as backends so the global LB can choose among them (capacity / utilization / health).

---

## Geo routing approach

| Phase | Behavior |
|-------|----------|
| **Now (basic)** | **Default = Google load balancing** across backends (serverless NEGs). Traffic tends toward **healthy** backends; exact algorithm is Google-managed (not “pure ping latency” in all cases). Good foundation for **one global hostname** and **multi-region resilience**. |
| **Future** | **Header-based hints** (e.g. `x-region: jo` / `x-region: eg`) — application or edge function can set policy; **no hard enforcement in orders-api yet** (see product backlog). |
| **Future** | Stricter **geo affinity** may use **Cloud Armor**, **custom metrics**, **Traffic Director**, or **separate URL maps / host rules** — design when requirements firm up. |

**Important:** If you need **strict** “Egypt always → `europe-west1`” and **Jordan always → `me-central1`**, that is **not** expressed by the minimal URL map in `scripts/setup-global-lb-https.sh` alone; plan additional routing rules or a dedicated geo layer.

---

## Scripts (additive)

| Script | Purpose |
|--------|---------|
| `scripts/setup-neg.sh` | Create **serverless NEGs** + **global backend service** + attach both backends. |
| `scripts/setup-global-lb-https.sh` | Reserve **global static IP**, optional **Google-managed SSL cert**, **URL map**, **target HTTPS proxy**, **forwarding rule** (:443). |

Run from **`backend/orders-api`** (or set paths accordingly). On Unix/macOS/Git Bash:

```bash
chmod +x scripts/setup-neg.sh scripts/setup-global-lb-https.sh
```

Scripts use **idempotent-style** checks (`describe` → create/skip) where practical. Re-running is usually safe for **create-if-missing** resources; changing **names**, **regions**, or **backend membership** may require manual `gcloud` cleanup or `update` commands.

**Order:** `setup-neg.sh` → `setup-global-lb-https.sh`.

### Environment variables (optional overrides)

| Variable | Default | Used in |
|----------|---------|---------|
| `GCP_PROJECT_ID` | `gcloud` config | both |
| `CLOUD_RUN_SERVICE` | `orders-api` | `setup-neg.sh` |
| `NEG_EU` / `NEG_ME` | `orders-api-eu` / `orders-api-me` | `setup-neg.sh` |
| `REGION_EU` / `REGION_ME` | `europe-west1` / `me-central1` | `setup-neg.sh` |
| `BACKEND_SERVICE` | `orders-api-backend` | both |
| `MANAGED_SSL_DOMAIN` | — | `setup-global-lb-https.sh` (e.g. `api.example.com`) |
| `SSL_CERT_NAME` | — | `setup-global-lb-https.sh` (use existing global cert instead of creating one) |

### Reference — manual `gcloud` (equivalent to scripts)

**Serverless NEGs**

```bash
gcloud compute network-endpoint-groups create orders-api-eu \
  --region=europe-west1 \
  --network-endpoint-type=serverless \
  --cloud-run-service=orders-api

gcloud compute network-endpoint-groups create orders-api-me \
  --region=me-central1 \
  --network-endpoint-type=serverless \
  --cloud-run-service=orders-api
```

**Backend service**

```bash
gcloud compute backend-services create orders-api-backend \
  --global \
  --load-balancing-scheme=EXTERNAL_MANAGED \
  --protocol=HTTP

gcloud compute backend-services add-backend orders-api-backend \
  --global \
  --network-endpoint-group=orders-api-eu \
  --network-endpoint-group-region=europe-west1

gcloud compute backend-services add-backend orders-api-backend \
  --global \
  --network-endpoint-group=orders-api-me \
  --network-endpoint-group-region=me-central1
```

**URL map, HTTPS proxy, forwarding rule** (requires a **global** `SSL_CERT_NAME`; create a [managed cert](https://cloud.google.com/load-balancing/docs/ssl-certificates/google-managed-certs) first or pass `--ssl-certificates=YOUR_SSL_CERT`)

```bash
gcloud compute url-maps create orders-api-map \
  --default-service=orders-api-backend

gcloud compute target-https-proxies create orders-api-proxy \
  --url-map=orders-api-map \
  --ssl-certificates=YOUR_SSL_CERT \
  --global

gcloud compute forwarding-rules create orders-api-https \
  --global \
  --target-https-proxy=orders-api-proxy \
  --ports=443
```

In practice, reserve a **global static IP** and attach it to the forwarding rule (`setup-global-lb-https.sh` does this via `--address`).

**Prerequisites**

- `gcloud` authenticated; project set (`gcloud config set project PROJECT_ID`).
- APIs enabled: **Compute Engine API**, **Serverless VPC Access** (if used), **Certificate Manager** / classic SSL certs API as applicable.
- Cloud Run services **`orders-api`** already deployed in **`europe-west1`** and **`me-central1`** (see `scripts/deploy.sh`).

---

## DNS record (after forwarding rule exists)

Point:

```text
api.yourdomain.com  →  <GLOBAL_FORWARDING_RULE_IP>
```

Use the **static IP** printed by `gcloud compute forwarding-rules describe orders-api-https --global`.

---

## Testing

### Basic health (no auth)

```bash
curl -sS "https://api.yourdomain.com/health"
```

Expect JSON with `ok` / `service: orders-api` (and PostgreSQL fields depending on env).

### Optional client hints (future / manual testing)

These headers are **not** interpreted by orders-api for routing today; they are placeholders for **future** routing or debugging:

```bash
curl -sS -H "x-region: jo" "https://api.yourdomain.com/health"
curl -sS -H "x-region: eg" "https://api.yourdomain.com/health"
```

### Internal ops health (requires key)

`GET /internal/ops/global-health` needs `SEARCH_INTERNAL_API_KEY` and header `x-internal-api-key` — see `docs/CLOUD_RUN.md`. Not suitable for anonymous LB health checks; use **`/health`** for probes.

---

## Operations notes

- **Quotas**: Global LBs and NEGs count against project quotas.
- **Costs**: Forwarding rules, egress, and Cloud Run invocations apply.
- **Rollbacks**: Keep previous Cloud Run revisions; NEGs reference the **service**, not a single revision tag (traffic split is configured on Cloud Run).

---

## Related docs

- `docs/CLOUD_RUN.md` — container, env, secrets placeholders, `/health` vs `/internal/ops/global-health`.
