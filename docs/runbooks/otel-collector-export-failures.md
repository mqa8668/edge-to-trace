# OtelCollectorExportFailures

Severity: ticket. Fires when the collector's failed span or metric point export rate is above zero for 5 minutes (`otelcol_exporter_send_failed_spans_total`, `otelcol_exporter_send_failed_metric_points_total`).

## What it means

The OpenTelemetry Collector cannot send traces to Tempo (`otlp/tempo`) or metrics to Prometheus (`otlphttp/prometheus`). Data is being dropped.

## Impact

Traces or span-based metrics have gaps. The SLO metrics are computed in the collector and sent to Prometheus, so a metrics export failure blinds the SLO alerts.

## First 5 minutes

1. Which exporter? Query: `sum by (exporter) (rate(otelcol_exporter_send_failed_spans_total[5m]))` and the same for `otelcol_exporter_send_failed_metric_points_total`.
2. Look at the stack dashboard: http://localhost:3000/d/e2t-overview.
3. Check the destinations are up: `up{job="tempo"}`, `up{job="prometheus"}`, and `docker compose --profile lite ps tempo prometheus`.
4. Collector logs: `make logs S=otel-collector | tail -50`.
5. Check for the memory limiter refusing data: `rate(otelcol_processor_refused_spans_total[5m])`.

## Likely causes

- Tempo is down, restarting, or out of memory.
- Prometheus OTLP receiver is not enabled (`--web.enable-otlp-receiver`), or Prometheus rejects old samples.
- Collector is over its memory limit and is refusing data.
- Tempo just restarted and is not ready yet (see `docs/troubleshooting.md`).

## Mitigation

- Restart the failing backend: `docker compose --profile lite up -d tempo` or `prometheus`.
- Raise `mem_limit` if a component is OOM-killed.
- Lower the load: `docker compose --profile lite stop k6`.

## Follow-up

- Confirm the failure rate is back to zero for 5 minutes.
- Accept that spans in the gap are lost. The collector is not a durable queue here.
