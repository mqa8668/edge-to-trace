# Architecture

Version 0.1, profile `lite`. The diagram is in the [README](../README.md#architecture). This page explains the flows around it.

## Components

| Group | Services |
|---|---|
| Demo app | `storefront` (Elixir/Phoenix, OTel SDK), `recs` (Python/FastAPI, OTel SDK), `catalog` (Go, no SDK), `postgres`, `k6` load generator |
| Telemetry | `otel-collector`, `beyla` (eBPF, attached to `catalog`), `alloy` (log shipper), `docker-socket-proxy` |
| Storage and query | `prometheus` (OTLP receiver, exemplar storage), `tempo`, `loki` |
| Alerting | `alertmanager`, `alert-sink`, optional Telegram |
| UI and helpers | `grafana`, `postgres-exporter`, `toolbox` (tools profile) |

## Request flow

`GET /api/products/:id` on `storefront` calls `catalog` (`GET /products/{id}`) and `recs` (`GET /recommendations?product_id=`) in parallel. `recs` calls `catalog` (`GET /products/popular`) and ranks the result in a custom span `recs.rank_candidates`. `POST /api/orders` calls `catalog` (`POST /reservations`), which runs a Postgres transaction with `SELECT ... FOR UPDATE`. One trace crosses Elixir, Python, Go and Postgres.

## Data flows

| Signal | Path |
|---|---|
| Traces | `storefront` and `recs` -> OTLP -> `otel-collector`. `catalog` -> Beyla (eBPF) -> OTLP -> `otel-collector`. Collector -> tail sampling -> Tempo. |
| Span metrics | Collector computes RED metrics and a service graph from spans before sampling, then sends them to Prometheus over OTLP (`/api/v1/otlp`). Exemplars carry `trace_id`. |
| App metrics | OTLP to the collector, then to Prometheus. |
| Platform metrics | Prometheus scrapes prometheus, alertmanager, otel-collector (:8888), loki, tempo, alloy, grafana, beyla (:8999), postgres-exporter and alert-sink every 15 s. |
| Logs | Containers with label `e2t.logs=true` log JSON to stdout. Alloy discovers them through the socket proxy, extracts `level` as a label and `trace_id`, `span_id` as structured metadata, and pushes to Loki. |
| Alerts | Prometheus evaluates rules every 15 s and sends to Alertmanager. Alertmanager posts webhooks to `alert-sink`, and to Telegram if configured. |

Health check spans (`/healthz`, `/readyz`) are dropped in the collector, and health access log lines are dropped in Alloy.

## Ports and networks

Two Docker networks:

- `app`: storefront, recs, catalog, postgres, postgres-exporter, k6, beyla, otel-collector, prometheus.
- `obs`: otel-collector, prometheus, tempo, loki, alloy, docker-socket-proxy, alertmanager, alert-sink, grafana.

The collector and Prometheus are on both. Postgres is only on `app`. This split is coarse, and it is the seed for edge zones in v0.2 and network policies in v0.4.

Published to the host, all bound to `127.0.0.1`:

| Port | Service |
|---|---|
| 8080 | storefront (`/api/products/1`) |
| 3000 | Grafana |
| 9090 | Prometheus |
| 9093 | Alertmanager |
| 9095 | alert-sink (`/alerts`) |

Internal only: collector OTLP 4317 and 4318 (health 13133, own metrics 8888), Tempo 3200 and 4317, Loki 3100, Alloy 12345, Beyla metrics 8999, catalog 8081, recs 8082, chaos admin ports 9000, socket proxy 2375. Scripts reach internal ports through the `toolbox` container.

## Correlation paths

- Metric to trace: spanmetrics histograms carry exemplars. Prometheus stores them. The Grafana Prometheus datasource maps `trace_id` to Tempo (`exemplarTraceIdDestinations`).
- Trace to logs: the Tempo datasource uses `tracesToLogsV2`, filtering Loki by trace ID.
- Log to trace: the Loki datasource has a derived field on `trace_id` that opens Tempo.
- Trace to metrics and service map: Tempo `tracesToMetrics` and `serviceMap` point at Prometheus (`traces_service_graph_*`).
- Go without an SDK: `catalog` reads the incoming W3C `traceparent` header and logs that `trace_id`. Beyla continues the same trace. See [ADR-0003](adr/0003-mixed-instrumentation.md).

## Dashboards

| Dashboard | URL |
|---|---|
| Platform overview | http://localhost:3000/d/e2t-overview |
| SLO detail | http://localhost:3000/d/e2t-slo (`var-slo=availability` or `latency`) |
| Service drill-down | http://localhost:3000/d/e2t-service (`var-service`) |
| Beyla / eBPF | http://localhost:3000/d/e2t-beyla |

## Failure modes

| Failure | What happens |
|---|---|
| Collector down | Apps log export warnings and keep serving. Traces and span metrics stop. SLO alerts go blind. `TargetDown` fires after 2 minutes. |
| Tempo down | Collector retries then drops. Metrics and logs continue. `OtelCollectorExportFailures` fires. |
| Prometheus down | No rule evaluation, so no alerts, and no `Watchdog` at the sink. |
| Alertmanager or sink down | Rules fire but nobody hears. `Watchdog` stops arriving. |
| Loki down | Alloy buffers briefly then drops. Traces and metrics continue. |
| Beyla cannot load eBPF | `catalog` produces no server spans. Everything else works. `make doctor` reports it. |
| Socket proxy down | Alloy cannot discover containers, so new logs stop. |
| Postgres down | Product reads and orders fail. `PostgresDown` pages. |
| Sampling drops a trace | An exemplar may point to a trace that is gone. Slow and failed traces are always kept, so incident exemplars resolve. |

## Deliberate shortcuts

- No migration framework. `db/init/*.sql` runs once when the Postgres volume is created.
- `GRAFANA_VIEWERS_CAN_EDIT` (default false, true under `make demo`) lets the anonymous viewer use Explore. Turn it off for any shared or public Grafana.
- Grafana allows an anonymous Viewer (`GRAFANA_ANONYMOUS_VIEWER=true`). This is safe only because every port binds to `127.0.0.1`. The admin password is generated and stored in `.env`.
- Beyla is the one powerful container: it has seven capabilities including SYS_ADMIN and shares the PID namespace of `catalog`. It is not privileged. See `SECURITY.md`.
- Single node for everything, local disks, no replication, no long-term storage.
- Chaos admin API is protected by a shared token in `.env`; it is internal only.
- Telegram delivery is not tested in CI.
