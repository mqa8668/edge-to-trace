# StorefrontAvailabilityBurn

Severity: page (fast burn) or ticket (slow burn). SLO: 99.5% of storefront `/api/*` requests do not return 5xx, over 30 days. See [docs/slo.md](../slo.md).

## What it means

The storefront is returning 5xx on `/api/*` fast enough to use up the 30-day error budget too soon. The page variant fires when the burn rate is at least 14.4x over both 1h and 5m, or at least 6x over both 6h and 30m. The ticket variant fires at 3x (1d and 2h) or 1x (3d and 6h).

## Impact

Customers see failed requests on product pages or orders. At 14.4x the budget is gone in about 2 days. At 100% errors the page alert fires within a few minutes.

## First 5 minutes

1. Open the SLO dashboard: http://localhost:3000/d/e2t-slo?var-slo=availability. Check burn rate per window and budget left.
2. Open the service drill-down: http://localhost:3000/d/e2t-service?var-service=storefront. Find which route has the errors.
3. Follow metric -> trace -> logs:
   - On the error-rate or latency panel, click an exemplar dot. Grafana opens the trace in Tempo.
   - In the trace, find the span with an error status. The deepest red span is usually the cause (catalog, recs or Postgres).
   - Click "Logs for this span" to open Loki filtered by the trace ID. Look for `level=error` lines.
4. No exemplar available? Search Tempo with TraceQL in Explore: `{ resource.service.name = "storefront" && status = error }`.
5. Check the error ratio directly in Prometheus (http://localhost:9090):

```
sum(rate(traces_span_metrics_calls_total{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route=~"/api/.*",http_response_status_code=~"5.."}[5m]))
/
sum(rate(traces_span_metrics_calls_total{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route=~"/api/.*"}[5m]))
```

6. Check platform health: http://localhost:3000/d/e2t-overview, and `docker compose --profile lite ps`.
7. Logs from the CLI: `make logs S=storefront`.

## Likely causes

- Fault injection left on: `make chaos-errors` returns 503 on 25% of calls. Reset it (see Mitigation).
- Postgres down or slow. If `PostgresDown` is also firing, fix that first; it inhibits the ticket variant of this alert.
- `catalog` or `recs` crashed or restarting (`docker compose --profile lite ps`).
- A bad deploy of storefront (check `service.version` on the service dashboard).

## Mitigation

- If chaos is active: `make chaos-reset`. Faults also expire on their own after 15 minutes.
- Restart a crashed dependency: `docker compose --profile lite up -d catalog` (or `recs`, `postgres`).
- Roll back the last change to `storefront` and rebuild with `make up`.

## Follow-up

- Confirm the alert resolves in Alertmanager (http://localhost:9093) and the sink (http://localhost:9095/alerts). The longer windows clear later than the short ones; see the latency runbook for why.
- Record the cause. If it was a real code defect, add a test.
- If the alert was noisy, review the SLO spec in `slo/storefront.yml`, not the generated file.
