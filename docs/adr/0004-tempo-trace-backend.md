# ADR-0004: Tempo as the trace backend

Status: Accepted

## Context

We need a trace store that Grafana can link to from metrics (exemplars), logs (derived fields) and back, and that fits in a few hundred MB.

## Decision

Run Grafana Tempo 3.1.0 as a single binary with the local backend (`/var/tempo` on a named volume). The OTLP gRPC receiver listens on 4317 inside the `obs` network. The collector is the only sender. Search uses TraceQL.

Configuration notes from the build:
- In Tempo 3 the retention setting lives under `backend_worker.compaction.block_retention` (set to 48h), not under the 2.x `compactor` block.
- The metrics-generator is off. RED and service graph metrics come from the collector (ADR-0006).
- Tempo and Loki images have no shell healthcheck. `scripts/smoke.sh` polls `/ready` through the toolbox container.
- Right after a restart, search can return nothing for a short time (see `docs/troubleshooting.md`).

## Consequences

- Grafana correlation works with plain datasource settings: `tracesToLogsV2`, `tracesToMetrics`, `serviceMap`.
- Local disk only. There is no replication and no object storage.
- Tempo 3 is new and many blog posts show 2.x config. We keep the config minimal and pinned.

## Alternatives considered

- Jaeger v2: OTel-native with a good UI, but weaker Grafana correlation and a second UI to explain.
- Tempo 2.x: more examples online, but we would start the lab on a line that is already being replaced.
