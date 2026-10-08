# Watchdog

Severity: none. This alert is meant to fire all the time.

## What it means

`Watchdog` has the expression `vector(1)`, so it always fires. Alertmanager routes it to `alert-sink` every minute. It is a dead man's switch: if you stop seeing it, the alerting path is broken, not the system.

## Impact

The Watchdog firing has no impact. The Watchdog missing means no other alert can reach you. Treat that as a page-level problem.

## First 5 minutes

1. Check the sink has recent Watchdog entries: `curl -s 'http://localhost:9095/alerts?alertname=Watchdog' | head -c 600`.
2. Check Prometheus is up and evaluating: http://localhost:9090/alerts and http://localhost:9090/targets.
3. Check Alertmanager received it: http://localhost:9093/#/alerts.
4. Check containers: `docker compose --profile lite ps prometheus alertmanager alert-sink`.
5. Check the Prometheus-to-Alertmanager link: `up{job="alertmanager"}` and `prometheus_notifications_dropped_total`.

## Likely causes

- Prometheus, Alertmanager or alert-sink is down or restarting.
- Alertmanager config is invalid after an edit (`make logs S=alertmanager`).
- The rule file was not loaded. Prometheus has no lifecycle reload here; restart it after adding rule files.
- Network problem between containers on the `obs` network.

## Mitigation

- Start whatever is down: `docker compose --profile lite up -d prometheus alertmanager alert-sink`.
- After fixing the config: `docker compose --profile lite restart alertmanager` (or `prometheus`).

## Follow-up

- Run `make smoke`. It asserts that Watchdog reached the sink and that a synthetic page alert is routed.
- If this was an outage of the alerting tier, check whether `AlertmanagerNotificationsFailing` or `TargetDown` should have caught it earlier.
