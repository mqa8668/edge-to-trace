# ADR-0006: OpenTelemetry Collector as the telemetry hub

Status: Accepted

## Context

Three languages, two instrumentation styles, one set of RED metrics wanted. We also want the SLO to survive changes to trace sampling.

## Decision

Run the upstream OpenTelemetry Collector (contrib image, pinned) between the apps and the backends. Pipelines in `otel-collector/config.yaml`:
- `traces/in`: OTLP in, then `memory_limiter`, `filter/health` (drop health check spans), `resource`; exports to the `spanmetrics` and `servicegraph` connectors and to `forward/sample`.
- `traces/sampled`: `tail_sampling` then `batch` to Tempo. Policies keep every error, every trace of 300 ms or more, and a baseline percentage (`TAIL_SAMPLING_BASELINE_PERCENT`, 100 in the lab).
- `metrics/derived`: spanmetrics and servicegraph output to Prometheus over OTLP (`/api/v1/otlp`).
- `metrics/apps`: app metrics to Prometheus.

Spanmetrics uses explicit buckets that include 300ms, so the latency SLO threshold is an exact bucket boundary, and exemplars are enabled.

The order is the point. RED metrics are computed before sampling, so they stay unbiased if the baseline is lowered.

## Consequences

- Uniform metrics for all services, however they are instrumented.
- Catch: an exemplar can point at a trace that sampling dropped. Slow and failed traces are always kept, so the exemplars you click during an incident resolve. With the lab default of 100% this does not occur.
- The spanmetrics connector is alpha and metric names after OTLP translation can change. Names are frozen in `docs/slo.md` and checked by smoke and promtool tests.
- The collector is a single point of failure for telemetry. `OtelCollectorExportFailures` watches its exporters.

## Alternatives considered

- Tempo metrics-generator: couples metrics to the trace store.
- Alloy as the only agent: possible, but hides the vendor-neutral collector many teams run.
