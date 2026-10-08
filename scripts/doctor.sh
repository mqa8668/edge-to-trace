#!/usr/bin/env bash
# Environment checks: Docker, memory, architecture, and whether Beyla (eBPF) can instrument the catalog service.
set -euo pipefail

ok=0
say() { printf '%-28s %s\n' "$1" "$2"; }

if ! docker info >/dev/null 2>&1; then
  say "docker" "NOT REACHABLE (start Docker Desktop, Colima or the daemon)"
  exit 1
fi
say "docker server" "$(docker version --format '{{.Server.Version}}')"
gib=$(( $(docker info --format '{{.MemTotal}}') / 1024 / 1024 / 1024 ))
say "memory for docker" "${gib} GiB"
say "architecture" "$(docker info --format '{{.Architecture}}')"
if docker compose version >/dev/null 2>&1; then
  say "compose" "$(docker compose version --short)"
else
  say "compose" "MISSING (Compose v2 plugin required)"; ok=1
fi
if [ "$gib" -lt 4 ]; then
  say "verdict" "WARNING: give Docker at least 4 GiB"; ok=1
fi
if [ -f .env ]; then say ".env" "present"; else say ".env" "missing (make up creates it)"; fi
# Kernel of the Docker VM/host, as seen by containers.
kernel=$(docker run --rm --pull=never alpine uname -r 2>/dev/null || true)
[ -n "$kernel" ] && say "docker kernel" "$kernel" || say "docker kernel" "unknown (pull alpine once, or run after make up)"
# What Beyla itself says is the ground truth.
if docker compose --profile lite ps --status running --format '{{.Service}}' 2>/dev/null | grep -qx beyla; then
  logs=$(docker compose --profile lite logs --no-log-prefix beyla 2>&1 || true)
  if grep -q 'instrumenting process' <<<"$logs"; then
    say "beyla" "instrumenting catalog"
  elif grep -q "couldn't load tracer\|operation not permitted\|permission denied" <<<"$logs"; then
    say "beyla" "NOT instrumenting. Set BEYLA_PRIVILEGED=1 in .env and re-run make up. Without it the stack still works; catalog shows only as a client span in traces."; ok=1
  elif grep -q 'cannot allocate memory' <<<"$logs"; then
    say "beyla" "NOT instrumenting: eBPF map creation hit the memory limit. Raise mem_limit for beyla in compose.yaml."; ok=1
  else
    say "beyla" "running, no instrumentation message yet (check: make logs S=beyla)"
  fi
else
  say "beyla" "not running"
fi
if [ "$ok" -eq 0 ]; then say "verdict" "OK"; fi
exit "$ok"
