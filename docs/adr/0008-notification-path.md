# ADR-0008: Notification path with an offline sink and optional Telegram

Status: Accepted

## Context

The demo and CI must work with no internet and no tokens. A reviewer should still be able to see a real notification channel.

## Decision

Alertmanager routes every alert to `alert-sink`, a small Go webhook receiver (`POST /webhook`, `GET /alerts`, on port 9095). Routes: `Watchdog` goes to the sink every minute, `severity=page` and `severity=ticket` go to their own receivers, and the default is the sink. `PostgresDown` inhibits the ticket variant of `StorefrontAvailabilityBurn` (cause over symptom).

Telegram is an override. It is used only when `secrets/telegram_bot_token.txt` and `secrets/telegram_chat_id.txt` exist (`compose.telegram.yaml`, `alertmanager/alertmanager.telegram.yml`, `alertmanager/templates/telegram.tmpl`). The message text is the same one the sink shows. The message is compact (header with severity, SLO, burn rate and remaining budget, start time with duration, then Dashboard, Traces and Runbook links; the Grafana links use `127.0.0.1` because Telegram drops links whose host is `localhost`) and a non-SLO alert shows its summary instead of the SLO rows. Alerts labelled `synthetic="true"` (the smoke test) are routed to the sink first and never reach Telegram. Page and ticket alerts can go to separate forum topics through `TELEGRAM_THREAD_PAGE` and `TELEGRAM_THREAD_TICKET`; Watchdog sends one silent heartbeat line every 12h to `TELEGRAM_THREAD_HEARTBEAT` while the sink keeps its 1m route. Unset means the main chat. Alertmanager does not expand environment variables, so the overlay rewrites `message_thread_id` lines at container start. Secrets are files, never environment variables, and `secrets/` is gitignored.

A page does not inhibit the ticket of the same SLO. Alertmanager sends no notification, including the resolved one, for an inhibited alert, so a ticket announced before the page fired would stay open in Telegram forever. Both alerts are delivered and resolve on their own; the ticket is silent and lives in its own topic.

## Consequences

- The Watchdog alert proves the path rule evaluation -> Alertmanager -> receiver every minute. `scripts/smoke.sh` checks it and posts a synthetic page alert.
- Telegram delivery is not covered by CI. It is checked by hand before a release.
- `AlertmanagerNotificationsFailing` is the only alert that can tell you the Telegram channel broke, and it cannot reach you through that same channel.

## Alternatives considered

- Telegram only: the demo breaks without a token.
- Email: needs an SMTP server, which is more to run and explain.
