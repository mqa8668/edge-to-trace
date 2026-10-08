#!/usr/bin/env bash
# API-level assertions for the running lite stack. Used by `make smoke` and CI.
# Needs: docker compose, curl, python3 on the host. Internal services (Tempo, Loki) are reached through the toolbox container.
set -euo pipefail
cd "$(dirname "$0")/.."
DOCKER=${DOCKER:-docker}
COMPOSE="$DOCKER compose --progress quiet ${COMPOSE_EXTRA:-} --profile lite --profile tools"
PROM=${PROM:-http://localhost:9090}
AM=${AM:-http://localhost:9093}
SINK=${SINK:-http://localhost:9095}

fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
tb() { $COMPOSE run --rm -T toolbox -fsS --max-time 10 "$@"; }
pq() { curl -fsS -G "$PROM/api/v1/query" --data-urlencode "query=$1"; }
py() { python3 -c "$1"; }

# 0. Tempo and Loki answer (they have no healthcheck in their images)
for url in http://tempo:3200/ready http://loki:3100/ready; do
  for _ in $(seq 1 30); do tb "$url" >/dev/null 2>&1 && break; sleep 3; done
  tb "$url" >/dev/null 2>&1 && ok "$url" || bad "$url not ready"
done

# 1. every scrape target is up
down=$(curl -fsS "$PROM/api/v1/targets" | py 'import sys,json
t=json.load(sys.stdin)["data"]["activeTargets"]
print(",".join(x["labels"]["job"] for x in t if x["health"]!="up"))')
[ -z "$down" ] && ok "all scrape targets up" || bad "targets down: $down"

# 2. traffic flows: storefront server-span count increases
q='sum(traces_span_metrics_calls_total{service_name="storefront",span_kind="SPAN_KIND_SERVER"})'
a=$(pq "$q" | py 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)')
sleep 30
b=$(pq "$q" | py 'import sys,json; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)')
py "import sys; sys.exit(0 if float('$b')>float('$a') else 1)" && ok "spanmetrics increasing ($a -> $b)" || bad "no traffic in spanmetrics ($a -> $b)"

# 3. a trace spans >= 3 services
best=0
for id in $(tb "http://tempo:3200/api/search?limit=10&q=%7B%20resource.service.name%3D%22storefront%22%20%7D" | py 'import sys,json; print(" ".join(t["traceID"] for t in json.load(sys.stdin).get("traces",[])))'); do
  c=$(tb "http://tempo:3200/api/traces/$id" | py '
import sys,json
d=json.load(sys.stdin)
s=set()
for b in d.get("batches",d.get("resourceSpans",[])):
    for a in b["resource"]["attributes"]:
        if a["key"]=="service.name": s.add(a["value"]["stringValue"])
print(len(s))')
  [ "$c" -gt "$best" ] && best=$c
done
[ "$best" -ge 3 ] && ok "tempo trace across $best services" || bad "no trace with >=3 services (best $best)"

# 4. exemplars on storefront duration
now=$(date +%s)
ex=$(curl -fsS -G "$PROM/api/v1/query_exemplars" --data-urlencode 'query=traces_span_metrics_duration_milliseconds_bucket{service_name="storefront"}' --data-urlencode "start=$((now-300))" --data-urlencode "end=$now" | py 'import sys,json; print(sum(len(s["exemplars"]) for s in json.load(sys.stdin)["data"]))')
[ "$ex" -ge 1 ] && ok "exemplars: $ex" || bad "no exemplars"

# 5. loki has storefront lines with trace ids
lk=$(tb -G "http://loki:3100/loki/api/v1/query_range" --data-urlencode 'query={service_name="storefront"} | trace_id != ""' --data-urlencode "start=$(( (now-600) ))000000000" --data-urlencode 'limit=5' | py 'import sys,json; print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))')
[ "$lk" -ge 1 ] && ok "loki lines with trace_id: $lk" || bad "no loki lines with trace_id"

# 6. alert path: Watchdog reached the sink, and a synthetic page alert is routed
curl -fsS "$SINK/alerts?alertname=Watchdog" | py 'import sys,json; sys.exit(0 if json.load(sys.stdin) else 1)' && ok "Watchdog reached alert-sink" || bad "Watchdog not at alert-sink"
curl -fsS -X POST "$AM/api/v2/alerts" -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"SmokeSynthetic","severity":"page","synthetic":"true"},"annotations":{"summary":"synthetic"}}]' >/dev/null
for _ in $(seq 1 20); do
  curl -fsS "$SINK/alerts?alertname=SmokeSynthetic" | py 'import sys,json; sys.exit(0 if json.load(sys.stdin) else 1)' && { ok "synthetic page alert delivered"; break; }
  sleep 3
done || true
curl -fsS "$SINK/alerts?alertname=SmokeSynthetic" | py 'import sys,json; sys.exit(0 if json.load(sys.stdin) else 1)' || bad "synthetic alert not delivered"

exit $fail
