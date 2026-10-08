# ADR-0003: Mixed instrumentation on purpose

Status: Accepted

## Context

The demo app has three services in three languages: `storefront` (Elixir/Phoenix), `recs` (Python/FastAPI) and `catalog` (Go). We want to show zero-code eBPF instrumentation (Grafana Beyla) next to SDK instrumentation, and be honest about where each works.

Beyla follows trace context only where it can read it at library level. Go is that case. For the BEAM, Beyla sees network calls but cannot follow context across the scheduler, so traces would break. The SDK also gives us custom spans (the `recs.rank_candidates` span used by the chaos scenario) and log correlation.

## Decision

- `catalog` (Go) has no tracing SDK. Beyla instruments it. The Go code only parses the incoming W3C `traceparent` header and logs that `trace_id`, which is the same trace Beyla continues.
- `storefront` and `recs` use the OpenTelemetry SDK and export OTLP to the collector.
- Beyla config selects only the process listening on port 8081 with an executable matching `*catalog`, so it never double-instruments the SDK services. `context_propagation` is disabled: catalog is a leaf, and it avoids header injection requirements.
- Beyla exports traces only. RED metrics for every service come from the collector's spanmetrics (ADR-0006).
- Beyla runs without `privileged`. It gets `cap_drop: [ALL]` plus BPF, PERFMON, SYS_PTRACE, NET_RAW, DAC_READ_SEARCH, CHECKPOINT_RESTORE and SYS_ADMIN, and shares the PID namespace of `catalog`.
- Measured: `mem_limit` must be 512m. eBPF map memory is charged to the container cgroup, and 256m failed with ENOMEM on Linux 6.8.

## Consequences

- Beyla is the one powerful container in the stack. The risk is documented in `SECURITY.md`.
- If Beyla cannot load (kernel without BTF, some Docker Desktop VMs), the stack still works. Traces lose the `catalog` server span. `make doctor` reports this.
- The SLIs do not depend on Beyla; they use `storefront` SERVER spans.

## Alternatives considered

- Beyla everywhere: broken traces for Elixir.
- SDK everywhere: simpler, but loses the zero-code comparison, which is the interesting part.
