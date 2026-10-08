# Sizing

What the lite profile costs. Numbers are measured, not estimated, unless marked pending.

## Measurement setup

- Linux 6.8 x86_64 VM, 12 vCPU.
- About 45 minutes of running, with k6 at 5 requests per second, plus one latency chaos run.
- `docker stats --no-stream`, memory in MiB.

## Memory and limits

| Service | Measured (MiB) | `mem_limit` |
|---|---|---|
| tempo | 333 (peak about 520 under chaos plus trace queries) | 768m |
| beyla | 305 | 512m |
| grafana | 237 idle, about 500 with several dashboards and Explore open | 640m |
| storefront | 154 | 256m |
| prometheus | 105 | 512m |
| loki | 104 | 384m |
| otel-collector | 94 | 256m |
| alloy | 70 | 192m |
| recs | 60 | 192m |
| postgres | 39 | 256m |
| docker-socket-proxy | 24 | 32m |
| alertmanager | 22 | 64m |
| k6 | 17 | 128m |
| postgres-exporter | 10 | 32m |
| catalog | 9 | 64m |
| alert-sink | 6 | 32m |
| **Total** | **about 1.54 GiB** | **4320 MiB (about 4.2 GiB)** |

The limit total is the sum of the `mem_limit` values in `compose.yaml`. The `toolbox` helper (32m, `tools` profile) runs only when a script calls it and is not counted.

CPU: about 45% of one core in total, across all containers.

Disk: under 5 GB with the default retention: Loki 72h, Tempo 48h, Prometheus 7 days or 2 GB, whichever comes first.

## Platforms

| Platform | Result |
|---|---|
| Linux 6.8 x86_64, 12 vCPU | Measured, table above |
| macOS Docker Desktop (Apple Silicon and Intel) | **Pending. Not yet measured.** |

Give Docker at least 4 GiB. `make doctor` and `scripts/bootstrap.sh` warn below that. The measured total is well under it, but Docker Desktop also needs room for its VM and for image builds.

## Limits raised after measurement

The first draft used smaller limits. Three were raised once real numbers were in:

- **beyla: 256m to 512m.** eBPF map memory is charged to the container's cgroup. With 256m, creating maps failed with ENOMEM on Linux 6.8 and Beyla did not instrument anything. Steady use is 305 MiB, and the limit has to cover map creation too.
- **grafana: 256m, 384m, then 640m.** 384m was OOM-killed over and over during the recording sessions (about 300 MiB heap plus 195 MiB page cache with several dashboards and Explore open), so the limit is now 640m. Earlier: 237 MiB measured is over 90% of 256m, which leaves no margin for a busy dashboard.
- **tempo: 384m to 512m to 768m.** A 512m limit was OOM-killed (anon RSS about 520 MiB) during a chaos run while traces were being queried, so the limit is now 768m. 333 MiB measured after 45 minutes with every trace kept (baseline sampling is 100%) is 87% of 384m, with more data still arriving.

Prometheus has a high limit (512m) and low use (105 MiB). It is kept high because memory grows with series count and retained exemplars (100000 max). Lower it only if you shorten retention.

## Profiles

| Profile | Status | Expected Docker memory |
|---|---|---|
| lite | v0.1, built | about 4 GiB |
| edge | planned v0.2 | about 5 GiB |
| full | planned v0.3 | about 14 to 16 GiB |
| k8s | planned v0.4 | about 8 GiB |

Only lite is built. The other figures are planning targets from the spec, not measurements.
