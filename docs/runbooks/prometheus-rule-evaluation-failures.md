# PrometheusRuleEvaluationFailures

Severity: ticket. Fires when `increase(prometheus_rule_evaluation_failures_total[5m]) > 0`.

## What it means

Prometheus tried to evaluate at least one recording or alerting rule and got an error. Alerts based on that rule may not fire, even if the condition is true.

## Impact

Silent loss of alerting for the affected rules. The SLO burn alerts are generated rules, so a failure there means a burning SLO may not page.

## First 5 minutes

1. Find the failing group: http://localhost:9090/rules (look for red health and the last error).
2. Query: `increase(prometheus_rule_evaluation_failures_total[5m]) > 0` and look at the `rule_group` label.
3. Read the error: `make logs S=prometheus | grep -i "rule" | tail -20`.
4. Check that the rules still parse: `docker run --rm --entrypoint promtool -v "$PWD:/w" -w /w prom/prometheus:v3.13.4 check rules prometheus/rules/platform.yml prometheus/rules/slo/storefront.generated.yml`.

## Likely causes

- A query returns too many series or hits a limit.
- Many-to-many matching error after a label change.
- The source metric is missing or renamed (for example the span metric names changed after a collector upgrade). Names are frozen in `docs/slo.md`.
- A rule file was edited by hand, or the generated SLO file drifted from `slo/storefront.yml`.

## Mitigation

- Fix the expression. For SLO rules, change `slo/storefront.yml` and run `make slo`.
- Prometheus has no lifecycle API enabled here and does not see new files after start. Restart it: `docker compose --profile lite restart prometheus`.
- Run `make test` to run the rule unit tests.

## Follow-up

- Add or extend a case in `tests/prometheus/` that would have caught it.
- Check `make smoke` passes.
