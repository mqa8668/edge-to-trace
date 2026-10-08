# Service level objectives

Two SLOs on the `storefront` service. They are declared in `slo/storefront.yml`, turned into Prometheus rules by Sloth (`make slo`), and the generated file `prometheus/rules/slo/storefront.generated.yml` is committed. Design reason: [ADR-0007](adr/0007-slo-with-sloth.md).

## Definitions

| SLO | Objective | Window | Good event | Bad event |
|---|---|---|---|---|
| `storefront-availability` | 99.5% | 30 days | `/api/*` request that does not return 5xx | `/api/*` SERVER span with `http_response_status_code=~"5.."` |
| `storefront-latency` | 99% | 30 days | `/api/*` request that completes in 300 ms or less | total requests minus the `le="300"` bucket |

Both use `storefront` SERVER spans only. The error budget is 0.5% of requests for availability and 1% for latency.

The 300 ms threshold is an exact histogram bucket boundary (`otel-collector/config.yaml` lists the buckets 5ms, 10ms, 25ms, 50ms, 100ms, 200ms, 300ms, 500ms, 800ms, 1s, 2s, 5s). There is no interpolation.

## Frozen metric names

These come from the collector's spanmetrics connector after Prometheus OTLP translation. The SLO queries and the promtool tests use them. If a collector or Prometheus upgrade changes them, `make smoke` fails, and this list and the SLO spec must be updated together.

| Metric | Type | Used for |
|---|---|---|
| `traces_span_metrics_calls_total` | counter | availability (errors and total), request rate |
| `traces_span_metrics_duration_milliseconds_bucket` | histogram buckets | latency (`le="300"`), percentiles, exemplars |
| `traces_span_metrics_duration_milliseconds_count` | histogram count | latency total |

Labels used: `service_name`, `span_kind` (value `SPAN_KIND_SERVER`), `http_route` (matched with `/api/.*`), `http_response_status_code`, and `le` on the bucket series.

Queries as written in the spec (error side only):

```
# availability
sum(rate(traces_span_metrics_calls_total{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route=~"/api/.*",http_response_status_code=~"5.."}[W]))
# latency
sum(rate(traces_span_metrics_duration_milliseconds_count{...}[W])) - sum(rate(traces_span_metrics_duration_milliseconds_bucket{...,le="300"}[W]))
```

`W` is each window that Sloth fills in. Sloth also generates recording rules such as `slo:current_burn_rate:ratio` and `slo:period_error_budget_remaining:ratio`, labelled with `sloth_id` (for example `storefront-availability`).

## Burn rate and windows

Burn rate is the error ratio divided by the budget ratio. A burn rate of 1 uses exactly the whole budget in 30 days. Sloth uses the default windows from the Google SRE workbook:

| Alert | Long window | Short window | Burn rate | Severity | Budget used when it fires | Time to fire at 100% errors, availability | Time to fire at 100% slow, latency |
|---|---|---|---|---|---|---|---|
| Page, fast | 1h | 5m | 14.4x | page | 2% of 30d budget | about 4.3 min | about 8.6 min |
| Page, slow | 6h | 30m | 6x | page | 5% | about 10.8 min | about 21.6 min |
| Ticket, fast | 1d | 2h | 3x | ticket | 10% | about 21.6 min | about 43.2 min |
| Ticket, slow | 3d | 6h | 1x | ticket | 10% | about 21.6 min | about 43.2 min |

Budget consumed is burn rate times window divided by 720 hours: 14.4 x 1h = 2%, 6 x 6h = 5%, 3 x 24h = 10%, 1 x 72h = 10%.

An alert fires when both windows of a pair are over the threshold. A page fires if either page pair is true. The time-to-fire figures are calculated, not measured. They assume windows full of healthy history and every request failing (or slow) from time zero: the long window needs `burn rate x budget ratio x window length` of bad traffic. Real times are a little longer because of the 15 s evaluation interval and the 15 s span metrics flush.

A short window alone would page on blips. A long window alone would keep paging long after the problem is fixed. Requiring both gives fast detection and fast clearing. The 6h/30m pair still clears slowly after a long incident; see the "Why it resolves slowly" section of the [latency runbook](runbooks/storefront-latency-burn.md).

## Why 4xx do not burn budget

A 4xx means the client sent a bad request: unknown product, invalid order body, missing field. The service did what it should. Counting those would let a scanner or a buggy client spend the error budget of everyone else. The availability SLO counts only 5xx, which are failures on our side. They still count in the total, so they dilute the error ratio.

A later milestone adds an edge SLO where 403 (WAF block) and 429 (rate limit) are excluded on purpose, for the same reason. That is planned for v0.2.

## Why the demo fires within minutes

The 30-day SLO is a reporting window, but the alerts use short windows, and Prometheus `rate()` averages only over the data that exists. On a fresh stack the 1h window holds only a few minutes of data, so a burst of slow requests fills most of it quickly.

`make chaos-latency` adds 800 ms to 60% of calls to `recs`. Only product detail requests go through `recs`, so the share of slow `/api/*` requests is lower than 60% but still far above the 1% budget, a burn rate of tens of times (the spec estimates 40x to 60x). With 100 times the threshold exceeded on a young stack, the page alert fires within a few minutes.

On a stack that has run for hours with healthy traffic, the same fault takes longer. For a slow ratio `r`, the 1h/14.4x pair needs about `0.144 x 60 / r` minutes for the latency SLO. With `r` = 0.5 that is about 17 minutes. The 5m window is not the limit.

## Alert names and labels

- `StorefrontAvailabilityBurn` and `StorefrontLatencyBurn`, each with `severity=page` and `severity=ticket` variants.
- Annotations: `runbook_url`, `dashboard_url`, `slo_objective` (readable target such as "99% under 300ms"), `burn_rate`, `budget_left` (percent, clamped at 0), `tempo_url`.
- Runbooks: [availability](runbooks/storefront-availability-burn.md), [latency](runbooks/storefront-latency-burn.md).
- Dashboard: http://localhost:3000/d/e2t-slo (variable `var-slo` is `availability` or `latency`).
