# AlertmanagerNotificationsFailing

Severity: page. Fires when `rate(alertmanager_notifications_failed_total[5m]) > 0` for 5 minutes.

## What it means

Alertmanager is trying to send notifications and failing. The `integration` label says which one: `webhook` (the alert-sink) or `telegram` if the Telegram override is on.

## Impact

Other alerts may be firing and nobody hears about them. If Telegram is the failing channel, this alert cannot reach you through it either. The alert sink still shows the message when it is up.

## First 5 minutes

1. Open Alertmanager: http://localhost:9093 and check the status page.
2. Query: `sum by (integration) (rate(alertmanager_notifications_failed_total[5m]))`.
3. Check the sink is alive: `curl -s http://localhost:9095/healthz` and `docker compose --profile lite ps alert-sink`.
4. Read Alertmanager logs: `make logs S=alertmanager | grep -i "notify\|error" | tail -20`.
5. If Telegram: check the two files `secrets/telegram_bot_token.txt` and `secrets/telegram_chat_id.txt` exist, are correct, and the host has internet access.

## Likely causes

- `alert-sink` is down or restarting.
- Telegram token or chat ID is wrong, revoked, or the bot was removed from the chat.
- No outbound internet from the Docker network.
- Telegram API rate limit.

## Mitigation

- Restart the sink: `docker compose --profile lite up -d alert-sink`.
- Fix or remove the Telegram secrets. Without the secret files the stack uses the sink only.
- Recreate Alertmanager after config changes: `docker compose --profile lite up -d --force-recreate alertmanager`.

## Follow-up

- Run `make smoke` to prove the synthetic page alert is delivered.
- Look at http://localhost:9095/alerts for anything that was missed while delivery failed.
