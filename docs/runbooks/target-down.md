# TargetDown

Severity: ticket. Fires when `up == 0` for 2 minutes for any scrape job.

## What it means

Prometheus cannot scrape one of its targets. The `job` label in the alert names it: prometheus, alertmanager, otel-collector, loki, tempo, alloy, grafana, beyla, postgres-exporter or alert-sink (see `prometheus/prometheus.yml`).

## Impact

Metrics from that component are missing, so dashboards and other alerts based on them are blind. If the target is the OpenTelemetry Collector, span-based SLO metrics stop too.

## First 5 minutes

1. List unhealthy targets and the scrape error: http://localhost:9090/targets (filter by "unhealthy").
2. Query: `up == 0`.
3. Check the container: `docker compose --profile lite ps`, then `make logs S=<service>`.
4. Check for a restart loop or an out-of-memory kill: `docker inspect -f '{{.State.OOMKilled}} {{.RestartCount}}' e2t-<service>-1`.
5. Check the platform dashboard: http://localhost:3000/d/e2t-overview.

## Likely causes

- The container exited or was OOM-killed (see `docs/sizing.md` for limits).
- The container is still starting, and the alert fired on a slow boot.
- Beyla: the process did not start because eBPF could not load (see `docs/troubleshooting.md`).
- A config change that moved the metrics port.

## Mitigation

- Restart it: `docker compose --profile lite up -d <service>`.
- If OOM-killed, raise `mem_limit` for that service in `compose.yaml` and recreate it.
- If Beyla only, the rest of the stack works without it. Fix it when convenient.

## Follow-up

- Confirm the target is up again at /targets and the alert clears.
- If the same target flaps, find the cause rather than raising the `for:` duration.
