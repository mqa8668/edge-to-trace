# Contributing

Small project, small rules. Open an issue before a large change.

## Before you push

```
make test     # app unit tests, promtool rule tests, Alertmanager route tests
make lint     # compose config, hadolint, shellcheck, gitleaks
make smoke    # needs the stack running (make up)
```

If you change `slo/storefront.yml`, run `make slo` and commit the regenerated `prometheus/rules/slo/storefront.generated.yml` together with it. Do not edit the generated file by hand.

Prometheus does not reload rule files while running. After adding or changing rules, restart it: `docker compose --profile lite restart prometheus`.

Install gitleaks as a pre-commit hook so secrets never reach history. Real secrets belong in `.env` or `secrets/`, both gitignored.

## Style

- Docs: plain English, short sentences, no emoji, no marketing words.
- Every new alert needs a runbook in `docs/runbooks/` with the headings What it means, Impact, First 5 minutes, Likely causes, Mitigation, Follow-up.
- Every new component needs an ADR in `docs/adr/` (Status, Context, Decision, Consequences, Alternatives considered).
- Pin new images as `tag@sha256`.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, shellcheck clean.

## Manual UI checklist (before a release)

Run on Linux amd64 and on macOS Docker Desktop. Start with `make up`, wait for healthy, then `make chaos-latency`.

- [ ] Exemplar click: on the latency panel of http://localhost:3000/d/e2t-service, click an exemplar and land in the Tempo trace.
- [ ] Trace to logs: from the trace, open logs for a span and see lines with the same trace ID.
- [ ] Logs to trace: in Loki Explore, click the `trace_id` derived field and land in the trace.
- [ ] Service map: the Tempo service map shows storefront, recs and catalog.
- [ ] `recs.rank_candidates` is about 800 ms with `chaos.injected=true`.
- [ ] Telegram message renders correctly (only if secrets are configured). Otherwise, alert-sink at http://localhost:9095/alerts shows the same text.
- [ ] `make chaos-reset`, and the alert resolves.
- [ ] Record memory with `docker stats --no-stream` and update `docs/sizing.md`.
