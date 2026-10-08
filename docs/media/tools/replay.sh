#!/bin/bash
# Replays the captured transcript of a real `make demo` run (progress counters removed, long URLs shortened).
f="$1"
printf 'storefront:   http://localhost:8080/api/products/1\ngrafana:      http://localhost:3000   (admin password in .env)\nprometheus:   http://localhost:9090\nalertmanager: http://localhost:9093\nalert-sink:   http://localhost:9095/alerts\n'
sleep 0.4
tr -d '\000' < "$f" | tr '\r' '\n' | sed -E 's/\x1b\[[0-9;]*m//g; s/\^@//g' | grep -v -E '^ *[0-9]+ (/ [0-9]+ )?s$' | cat -s | while IFS= read -r line; do
  if [ ${#line} -gt 118 ]; then line="${line:0:115}..."; fi
  printf '%s\n' "$line"
  case "$line" in
    *"Waiting for the page"*) sleep 3 ;;
    *"Fired after"*) sleep 1 ;;
    *) sleep 0.08 ;;
  esac
done
