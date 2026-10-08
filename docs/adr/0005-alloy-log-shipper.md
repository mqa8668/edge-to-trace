# ADR-0005: Grafana Alloy as the log shipper

Status: Accepted

## Context

Promtail, the usual choice, was announced as end of life on 2026-03-02. Containers log JSON to stdout, and we need Docker metadata (service name, container) and the trace ID on each line.

## Decision

Use Grafana Alloy. `alloy/config.alloy` does this:
1. `discovery.docker` finds containers through the socket proxy (ADR-0010) at `tcp://docker-socket-proxy:2375`.
2. `discovery.relabel` keeps only containers with the label `e2t.logs=true` and maps the compose service to `service_name`.
3. `loki.source.docker` reads the logs.
4. `loki.process` parses JSON, keeps `level` as a label, stores `trace_id` and `span_id` as Loki structured metadata (not labels, to avoid cardinality), and drops `/healthz` and `/readyz` access lines.
5. `loki.write` pushes to Loki.

Measured: discovery through the proxy needs both `CONTAINERS=1` and `NETWORKS=1` on the proxy. Without `NETWORKS`, Alloy gets a 403.

Alloy runs as user 65534 with a read-only root and a tmpfs for its storage path.

## Consequences

- One agent, and its config is plain text in the repo.
- The `e2t.logs` label is opt-in, so infrastructure containers are not shipped by accident.
- The Alloy config syntax is its own language; contributors need to learn a little of it.

## Alternatives considered

- Promtail: end of life.
- OTel Collector `filelog`: no Docker metadata without extra plumbing.
