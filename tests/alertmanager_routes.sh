#!/usr/bin/env bash
# Routing and inhibition checks for alertmanager/alertmanager.yml (run through the Alertmanager image, no local install).
set -euo pipefail
cd "$(dirname "$0")/.."
AM_IMAGE=$(grep -o 'prom/alertmanager:[^ ]*' compose.yaml | head -1)
amtool() { ${DOCKER:-docker} run --rm --entrypoint amtool -v "$PWD/alertmanager:/c:ro" "$AM_IMAGE" "$@"; }
amtool check-config /c/alertmanager.yml >/dev/null
r() { amtool config routes test --config.file=/c/alertmanager.yml "$@" | tr -d '\r'; }
[ "$(r severity=page alertname=StorefrontLatencyBurn)" = page ]
[ "$(r severity=ticket alertname=TargetDown)" = ticket ]
[ "$(r alertname=Watchdog severity=none)" = sink ]
[ "$(r severity=page alertname=SmokeSynthetic synthetic=true)" = sink ]
# the Telegram variant keeps the same tree: synthetic alerts stay in the sink, real pages go to Telegram
rt() { amtool config routes test --config.file=/c/alertmanager.telegram.yml "$@" | tr -d '\r'; }
[ "$(rt severity=page alertname=SmokeSynthetic synthetic=true)" = sink ]
[ "$(rt severity=page alertname=StorefrontLatencyBurn)" = page ]
[ "$(rt alertname=Watchdog severity=none)" = "sink,heartbeat" ]
echo "alertmanager routes: ok"
