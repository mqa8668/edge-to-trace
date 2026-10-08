# StorefrontLatencyBurn

Severity: page (fast burn) or ticket (slow burn). SLO: 99% of storefront `/api/*` requests complete in under 300 ms, over 30 days. See [docs/slo.md](../slo.md).

## What it means

Too many `/api/*` requests are slower than 300 ms, fast enough to use up the 30-day budget too soon. The page variant fires at 14.4x over both 1h and 5m, or at 6x over both 6h and 30m. The ticket variant fires at 3x (1d and 2h) or 1x (3d and 6h).

## Impact

Pages load slowly. Nothing is failing, but users wait. If storefront has timeouts upstream, slow calls may turn into errors.

## First 5 minutes

1. Open the SLO dashboard: http://localhost:3000/d/e2t-slo?var-slo=latency.
2. Open the service drill-down: http://localhost:3000/d/e2t-service?var-service=storefront. Look at p95 and p99.
3. Follow metric -> trace -> logs:
   - On the latency panel, click an exemplar dot above the 300 ms line. Grafana opens that trace in Tempo.
   - Read the waterfall. Find the longest span. In the chaos scenario it is `recs.rank_candidates` at about 800 ms, with the attribute `chaos.injected=true`.
   - Click "Logs for this span" to see the log lines with the same `trace_id` in Loki.
4. Without an exemplar, search Tempo: `{ resource.service.name = "recs" && name = "recs.rank_candidates" && duration > 500ms }`, or `{ resource.service.name = "storefront" && duration > 300ms }`.
5. Compare services at http://localhost:3000/d/e2t-service?var-service=recs and `var-service=catalog`.
6. Check the share of slow requests in Prometheus (http://localhost:9090):

```
1 - (
  sum(rate(traces_span_metrics_duration_milliseconds_bucket{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route=~"/api/.*",le="300"}[5m]))
  /
  sum(rate(traces_span_metrics_duration_milliseconds_count{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route=~"/api/.*"}[5m]))
)
```

7. Check eBPF view of catalog: http://localhost:3000/d/e2t-beyla.

## Likely causes

- Fault injection left on: `make chaos-latency` adds 800 ms to 60% of calls to `recs`.
- `recs` ranking is slow, or `catalog` is slow (lock waits on `SELECT ... FOR UPDATE` during orders).
- Resource pressure: a container near its `mem_limit`, or a busy Docker VM.

## Mitigation

- If chaos is active: `make chaos-reset`. Faults also expire after 15 minutes.
- Restart the slow service if it is stuck: `docker compose --profile lite restart recs`.
- Reduce load by stopping the load generator: `docker compose --profile lite stop k6`.

## Why it resolves slowly

The page alert is the OR of two window pairs: 1h and 5m at 14.4x, and 6h and 30m at 6x. After an incident ends, the 5m/1h pair clears in about 5 minutes. The 6h/30m pair can keep the page firing for 20 to 30 minutes, because the 30m window still holds the bad minutes and the 6h window holds even more.

This is correct multi-window behaviour, not a bug. The long window stops a short blip from paging. The short window makes sure the alert clears once the problem is gone. The price is that the clear takes as long as the slower pair needs.

Measured on a Linux 6.8 VM with the default chaos (800 ms on 60% of `recs` calls, k6 at 5 requests per second):

| Run | Detection | Resolve after `make chaos-reset` |
|---|---|---|
| Cold start, 10 minutes of baseline, page fired as soon as the burn was seen | 118 s | 306 s in Prometheus, 336 s at the alert sink (Alertmanager `group_interval` of 30 s adds the rest) |
| Fault left on for about 17 minutes, then reset | under 5 min | 27 minutes |

So the rules are not misconfigured. There is no `for` or `keep_firing_for` on the generated alerts, and Alertmanager's `group_interval` is 30 s. The time to resolve is set by the 30 minute window: the page stays up until the share of slow requests in the last 30 minutes falls under 6% (6x the 1% budget). A short incident clears in about five minutes; a long one holds the page for as long as it takes the 30 minute window to empty out. On a cold stack the windows hold little data, so the very first burn rates are inflated and fire quickly.

The acceptance criterion is therefore "resolved within about 30 minutes of the fault ending, and within 6 minutes after a short incident".

Do not silence the alert to make it go away. Confirm the fix with the 5m error ratio query above, then wait.

## Follow-up

- Confirm resolution in Alertmanager (http://localhost:9093) and the sink (http://localhost:9095/alerts).
- If the cause was a real regression, add a latency test or a span attribute that would have made it obvious.
- If the 300 ms threshold no longer matches reality, change `slo/storefront.yml`, run `make slo`, and commit both files.
