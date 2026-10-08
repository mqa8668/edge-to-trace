# LokiIngestionFailing

Severity: ticket. Fires when Loki discards samples, or answers pushes with a 5xx, for 5 minutes.

## What it means

Alloy is sending logs and Loki is rejecting or failing them. Discards come from limits (rate, stream count, line age or size). 5xx responses mean Loki itself is unhealthy.

## Impact

Logs are missing. The trace-to-logs and log-to-trace links stop working for that time range.

## First 5 minutes

1. Query the reason: `sum by (reason) (rate(loki_discarded_samples_total[5m]))`.
2. Query 5xx: `sum by (status_code) (rate(loki_request_duration_seconds_count{route="loki_api_v1_push"}[5m]))`.
3. Loki readiness: `docker compose --profile lite --profile tools run --rm -T toolbox -fsS http://loki:3100/ready`.
4. Loki logs: `make logs S=loki | tail -50`. Alloy logs: `make logs S=alloy | tail -50`.
5. Check the container is not near its limit (`docker stats --no-stream`).

## Likely causes

- Ingestion limit exceeded (`ingestion_rate_mb: 8`, `max_streams_per_user: 5000` in `loki/config.yaml`), for example a log flood.
- Too many label values: a high-cardinality field was turned into a label. Trace IDs must stay structured metadata.
- Loki is out of memory or disk.
- Old log lines rejected after Alloy was stopped for a while.

## Mitigation

- Stop the flood at the source. Check which service is noisy with `{service_name=~".+"}` volume in Explore.
- Remove any new high-cardinality label from `alloy/config.alloy`.
- Restart Loki if it is unhealthy: `docker compose --profile lite restart loki`.

## Follow-up

- Tune limits only after the cause is known.
- Remember retention is 72h. Gaps older than that cannot be backfilled.
