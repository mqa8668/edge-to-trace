# Security

edge-to-trace is a local lab. It is not meant to be exposed to a network or to run production traffic.

## Reporting a problem

Open a private security advisory on the GitHub repository, or email the maintainer through the address on the GitHub profile. Please do not file public issues for security problems. This is a one-person project; expect a reply in a few days, not hours.

## Defaults

- All published ports bind to `127.0.0.1`: 8080, 3000, 9090, 9093, 9095.
- No default credentials. `scripts/bootstrap.sh` generates the Postgres password, the Grafana admin password and the chaos admin token into `.env` and sets its mode to 600. It refuses to continue if `.env` is world-accessible. `.env` and `secrets/` are gitignored.
- `make demo` also sets `GRAFANA_VIEWERS_CAN_EDIT=true` so the anonymous viewer can open Explore (exemplar and trace links need it). That setting is off for plain `make up`. A public, read-only Grafana (planned for v0.4, see the roadmap) must keep it off and use a dedicated read-only role or a proxy that blocks Explore.
- Grafana allows an anonymous Viewer when `GRAFANA_ANONYMOUS_VIEWER=true` (the default). Set it to `false` if other users share your machine or you change the port binding.
- Third-party images are pinned as `tag@sha256`. Our own images are built locally.
- Containers use `no-new-privileges`. Most also drop all capabilities and use a read-only root filesystem. Postgres, Alloy and postgres-exporter run as non-root users.
- gitleaks runs in `make lint`.

## Known exceptions

- **Beyla** (eBPF) is the one powerful container. It runs without `privileged` but with these capabilities: BPF, PERFMON, SYS_PTRACE, NET_RAW, DAC_READ_SEARCH, CHECKPOINT_RESTORE and SYS_ADMIN. It also shares the PID namespace of `catalog`. SYS_ADMIN and SYS_PTRACE together are close to root on the host kernel. If Beyla cannot start on your host, `BEYLA_PRIVILEGED=1` selects a privileged override, which is broader still. Only use it on a machine you control.
- **docker-socket-proxy** mounts `/var/run/docker.sock` read-only and exposes only the containers and networks API groups. Read access still shows container environment variables. It does not use the read-only root and capability drop that the other containers use.
- The **chaos admin API** (port 9000 on the demo services) is not published to the host and needs the `X-Chaos-Token` header. The token is in `.env`.
- **Telegram** (optional): the bot token and chat ID are read from `secrets/telegram_bot_token.txt` and `secrets/telegram_chat_id.txt`. Do not put them in `.env`.
- The lab has no TLS between containers and no authentication on internal ports. That is by design for a single-host lab.

## Scope

Reports about the lab's own configuration are welcome. Issues in upstream projects (Grafana, Prometheus, and so on) should go to those projects.
