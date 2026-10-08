#!/usr/bin/env bash
# Create .env from .env.example with random secrets, and sanity-check the Docker host.
set -euo pipefail
cd "$(dirname "$0")/.."

fill() { # fill KEY in .env when blank
  local key=$1 val
  if grep -Eq "^${key}=\s*$" .env; then
    val=$(openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-24)
    # portable in-place edit (GNU and BSD sed)
    sed "s|^${key}=.*|${key}=${val}|" .env >.env.tmp && mv .env.tmp .env
    echo "bootstrap: generated ${key}"
  fi
}

if [ ! -f .env ]; then
  cp .env.example .env
  echo "bootstrap: created .env from .env.example"
fi
chmod 600 .env

perm=$(stat -c '%a' .env 2>/dev/null || stat -f '%Lp' .env)
if [ "${perm: -1}" != "0" ]; then
  echo "bootstrap: .env is world-accessible (mode ${perm}); refusing to continue" >&2
  exit 1
fi

for k in POSTGRES_PASSWORD CHAOS_TOKEN GRAFANA_ADMIN_PASSWORD; do fill "$k"; done

if ! command -v docker >/dev/null 2>&1; then
  echo "bootstrap: docker not found" >&2
  exit 1
fi
mem=$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)
mem=${mem:-0}
gib=$((mem / 1024 / 1024 / 1024))
arch=$(docker info --format '{{.Architecture}}' 2>/dev/null || true)
arch=${arch:-unknown}
echo "bootstrap: docker memory ${gib} GiB, architecture ${arch}"
if [ "$gib" -lt 4 ]; then
  echo "bootstrap: WARNING docker has less than 4 GiB; the lite profile needs about 4 GiB once the observability tier is added" >&2
fi
