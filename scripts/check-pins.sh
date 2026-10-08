#!/usr/bin/env bash
# Every third-party image must be pinned by digest. Locally built images (e2t/*) are exempt.
set -euo pipefail
cd "$(dirname "$0")/.."
bad=0
while IFS= read -r line; do
  img=$(sed -E 's/^[^:]*:[0-9]+:[[:space:]]*image:[[:space:]]*//' <<<"$line")
  case "$img" in e2t/*) continue ;; esac
  grep -q '@sha256:' <<<"$img" || { echo "unpinned image: $line"; bad=1; }
done < <(grep -Hn -E '^[[:space:]]*image:' compose*.yaml | grep -v -E 'image:[[:space:]]*e2t/')
while IFS= read -r line; do
  grep -q '@sha256:' <<<"$line" || { echo "unpinned FROM: $line"; bad=1; }
done < <(grep -Hn -E '^FROM ' apps/*/Dockerfile db/Dockerfile | grep -v -E 'FROM (build|deps|compile|test|runtime)\b' | grep -v -E 'FROM [a-z]+ AS')
grep -rn -E ':latest\b' compose*.yaml apps/*/Dockerfile db/Dockerfile && { echo "latest tag found"; bad=1; }
[ "$bad" -eq 0 ] && echo "pins ok"
exit "$bad"
