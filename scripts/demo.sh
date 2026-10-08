#!/usr/bin/env bash
# usage: demo.sh run | reset [--wait]
# run:   the stack is already up (make demo does that). Wait for baseline load, inject latency, follow the alert
#        to the trace, print clickable links.
# reset: remove injected faults; with --wait also wait for the resolved notification.
set -euo pipefail
cd "$(dirname "$0")/.."

DOCKER=${DOCKER:-docker}
COMPOSE="$DOCKER compose ${COMPOSE_EXTRA:-} --progress quiet --profile lite --profile tools"
PROM=${PROM:-http://localhost:9090}
SINK=${SINK:-http://localhost:9095}
GRAFANA=${GRAFANA:-http://localhost:3000}
BASELINE_SECONDS=${BASELINE_SECONDS:-120}
FIRE_TIMEOUT=${FIRE_TIMEOUT:-600}
ALERT=StorefrontLatencyBurn

b() { printf '\033[1m%s\033[0m\n' "$*"; }
step() { printf '\n'; b "$1"; }
tb() { $COMPOSE run --rm -T toolbox -fsS --max-time 10 "$@"; }
urlenc() { python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
page_status() { # newest page-severity record for the alert: firing, resolved or none
  curl -fsS "$SINK/alerts?alertname=$ALERT" | python3 -c '
import sys, json
a = [x for x in json.load(sys.stdin) if x["labels"].get("severity") == "page"]
print(a[0]["status"] if a else "none")'
}

reset() {
  scripts/chaos.sh reset
  if [ "${1:-}" = "--wait" ]; then
    b "Waiting for the resolved notification (the 6h/30m window can hold the page for 20 to 30 minutes)..."
    local t0=$SECONDS
    while [ "$(page_status)" = firing ]; do sleep 10; done
    echo "Resolved after $((SECONDS - t0)) s."
  else
    echo "Faults removed. The page alert resolves once the 30 minute window recovers; watch $SINK/alerts?alertname=$ALERT"
  fi
}

case "${1:-run}" in
  reset) shift; reset "${1:-}"; exit 0 ;;
  run) ;;
  *) echo "usage: $0 run | reset [--wait]" >&2; exit 2 ;;
esac

set -a
# shellcheck disable=SC1091
. ./.env
set +a

step "1. Waiting for the stack"
for i in $(seq 1 60); do
  curl -fsS "$PROM/-/ready" >/dev/null 2>&1 && curl -fsS "$SINK/healthz" >/dev/null 2>&1 && break
  sleep 3
  [ "$i" = 60 ] && { echo "stack is not answering; try: make ps" >&2; exit 1; }
done
for url in http://tempo:3200/ready http://loki:3100/ready; do
  for _ in $(seq 1 40); do tb "$url" >/dev/null 2>&1 && break; sleep 3; done
done
echo "Stack is up. k6 is sending about 5 requests per second to the storefront."

step "2. Baseline traffic (${BASELINE_SECONDS} s)"
echo "Dashboard: $GRAFANA/d/e2t-overview?refresh=10s   (user admin, password in .env, or just browse as anonymous viewer)"
for ((s = 0; s < BASELINE_SECONDS; s += 10)); do
  printf '\r  %3d / %d s' "$s" "$BASELINE_SECONDS"
  sleep 10
done
printf '\n'

if [ "$(page_status)" = firing ]; then
  echo "An earlier $ALERT page is still firing. Run: make demo-reset WAIT=1   and start again." >&2
  exit 1
fi

step "3. Injecting latency into recs (800 ms on 60% of calls)"
t_inject=$(date +%s)
scripts/chaos.sh latency
echo "What happens next: storefront waits at most 400 ms for recs, so requests slow down, the share over 300 ms"
echo "climbs, and the multi-window burn rate crosses 14.4x on both the 1h and 5m windows."

step "4. Waiting for the page: $ALERT (up to $((FIRE_TIMEOUT / 60)) min)"
while [ "$(page_status)" != firing ]; do
  el=$(( $(date +%s) - t_inject ))
  printf '\r  %3d s' "$el"
  [ "$el" -ge "$FIRE_TIMEOUT" ] && { printf '\n'; echo "Did not fire within ${FIRE_TIMEOUT}s. Check $PROM/alerts" >&2; exit 1; }
  sleep 5
done
printf '\n'
b "Fired after $(( $(date +%s) - t_inject )) s. This is what Telegram (or any chat) shows:"
echo
curl -fsS "$SINK/messages?alertname=$ALERT&status=firing" | sed -n '1,/^$/p' | sed 's/^/    /'

step "5. From the alert to the slow span"
now=$(date +%s)
tid=$(curl -fsS -G "$PROM/api/v1/query_exemplars" \
  --data-urlencode 'query=traces_span_metrics_duration_milliseconds_bucket{service_name="storefront",span_kind="SPAN_KIND_SERVER",http_route="/api/products/:id"}' \
  --data-urlencode "start=$((now - 300))" --data-urlencode "end=$now" | python3 -c '
import sys, json
best = None
for s in json.load(sys.stdin)["data"]:
    for e in s["exemplars"]:
        v = float(e["value"])
        if best is None or v > best[0]:
            best = (v, e["labels"]["trace_id"])
print(best[1] if best else "")')
if [ -n "$tid" ]; then
  tempo_pane=$(urlenc "{\"a\":{\"datasource\":\"tempo\",\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"tempo\",\"uid\":\"tempo\"},\"queryType\":\"traceql\",\"query\":\"$tid\"}]}}")
  loki_pane=$(urlenc "{\"a\":{\"datasource\":\"loki\",\"queries\":[{\"refId\":\"A\",\"datasource\":{\"type\":\"loki\",\"uid\":\"loki\"},\"expr\":\"{service_name=~\\\".+\\\"} | trace_id=\\\"$tid\\\"\"}]}}")
  slow=$(tb "http://tempo:3200/api/traces/$tid" | python3 -c '
import sys, json
rows = []
for b in json.load(sys.stdin).get("batches", []):
    svc = [a["value"]["stringValue"] for a in b["resource"]["attributes"] if a["key"] == "service.name"][0]
    for ss in b["scopeSpans"]:
        for s in ss["spans"]:
            rows.append((int(s["endTimeUnixNano"]) - int(s["startTimeUnixNano"]), svc, s["name"]))
rows = sorted(set(rows), reverse=True)
for d, svc, n in rows[:4]:
    print("    %7.1f ms  %-10s %s" % (d / 1e6, svc, n))' 2>/dev/null || true)
  echo "Slowest exemplar trace: $tid"
  echo "$slow"
  echo
  echo "  Trace in Tempo:   $GRAFANA/explore?schemaVersion=1&panes=$tempo_pane"
  echo "  Logs of the trace: $GRAFANA/explore?schemaVersion=1&panes=$loki_pane"
else
  echo "No exemplar yet; open the latency panel and click a dot instead."
fi
echo "  Overview:          $GRAFANA/d/e2t-overview?from=$(( (t_inject - 300) * 1000 ))&to=now&refresh=10s"
echo "  SLO detail:        $GRAFANA/d/e2t-slo?var-slo=latency&from=$(( (t_inject - 300) * 1000 ))&to=now&refresh=10s"
echo "  Alerts:            $SINK/alerts?alertname=$ALERT     Alertmanager: http://localhost:9093"
echo "  Runbook:           docs/runbooks/storefront-latency-burn.md"

step "6. Clean up"
echo "The fault expires on its own after 15 minutes. To end it now:  make demo-reset   (WAIT=1 to wait for the resolve)"
