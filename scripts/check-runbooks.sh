#!/usr/bin/env bash
# Every runbook_url must point at an existing file in docs/runbooks/.
set -euo pipefail
cd "$(dirname "$0")/.."
bad=0
for f in $(grep -rhoE 'runbook_url: *"?https://github.com/[^ "]+/blob/main/docs/runbooks/[a-z-]+\.md' prometheus slo | sed -E 's#.*/docs/runbooks/##' | sort -u); do
  [ -f "docs/runbooks/$f" ] || { echo "missing runbook: docs/runbooks/$f"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "runbooks ok"
exit "$bad"
