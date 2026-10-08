#!/usr/bin/env bash
# usage: chaos.sh latency|errors|reset [TARGET]
# latency: 800 ms on 60% of calls, default target recs (SDK span, works everywhere); TARGET=catalog shows the Beyla path.
# errors:  503 on 25% of calls, default target catalog.
# The admin ports are internal, so the call goes through the toolbox container.
set -euo pipefail
cd "$(dirname "$0")/.."

mode=${1:-}
case "$mode" in
  latency) target=${2:-${TARGET:-recs}} ;;
  errors) target=${2:-${TARGET:-catalog}} ;;
  reset) target=${2:-${TARGET:-all}} ;;
  *) echo "usage: $0 latency|errors|reset [TARGET]" >&2; exit 2 ;;
esac

set -a
# shellcheck disable=SC1091
. ./.env
set +a
: "${CHAOS_TOKEN:?CHAOS_TOKEN missing in .env}"

# Best effort: mark the dashboards so the effect of the fault is visible (orange line "Chaos injected").
annotate() { # annotate TEXT
  [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ] || return 0
  curl -fsS --max-time 3 -u "admin:${GRAFANA_ADMIN_PASSWORD}" -H 'Content-Type: application/json' \
    -d "{\"tags\":[\"chaos\"],\"text\":\"$1\",\"time\":$(( $(date +%s) * 1000 ))}" \
    "http://localhost:${GRAFANA_PORT:-3000}/api/annotations" >/dev/null 2>&1 || true
}

call() { # call METHOD TARGET [JSON]
  local method=$1 host=$2 body=${3:-}
  local args=(-fsS --max-time 5 -X "$method" -H "X-Chaos-Token: ${CHAOS_TOKEN}")
  if [ -n "$body" ]; then args+=(-H 'Content-Type: application/json' -d "$body"); fi
  ${DOCKER:-docker} compose ${COMPOSE_EXTRA:-} --progress quiet --profile lite --profile tools run --rm -T toolbox "${args[@]}" "http://${host}:9000/admin/chaos"
  echo
}

case "$mode" in
  latency)
    call POST "$target" '{"latency_ms":800,"latency_ratio":0.6,"error_ratio":0.0,"ttl_seconds":900}'
    annotate "chaos: 800 ms on 60% of calls to ${target}"
    echo "chaos: 800 ms on 60% of calls to ${target}; auto-expires in 15 min" ;;
  errors)
    call POST "$target" '{"latency_ms":0,"latency_ratio":0.0,"error_ratio":0.25,"ttl_seconds":900}'
    annotate "chaos: 503 on 25% of calls to ${target}"
    echo "chaos: 503 on 25% of calls to ${target}; auto-expires in 15 min" ;;
  reset)
    if [ "$target" = all ]; then
      for t in storefront catalog recs; do call DELETE "$t"; done
    else
      call DELETE "$target"
    fi
    annotate "chaos reset (${target})"
    echo "chaos: reset" ;;
esac
