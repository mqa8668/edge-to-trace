# Troubleshooting

Start with `make doctor`. It checks Docker, memory, architecture, the Docker VM kernel and whether Beyla is instrumenting.

## Beyla is not instrumenting

Symptoms: no `catalog` server spans in Tempo, empty Beyla dashboard (http://localhost:3000/d/e2t-beyla), `make doctor` says "NOT instrumenting". The rest of the stack still works.

1. Read the log: `make logs S=beyla | tail -50`. A healthy start contains "instrumenting process".
2. "cannot allocate memory" or ENOMEM: the `mem_limit` is too small. eBPF map memory is charged to the container cgroup. It needs 512m (256m failed on Linux 6.8). Check the value in `compose.yaml` and recreate: `docker compose --profile lite up -d beyla`.
3. "operation not permitted" or "permission denied": the capability set is not enough on this host. Beyla runs with BPF, PERFMON, SYS_PTRACE, NET_RAW, DAC_READ_SEARCH, CHECKPOINT_RESTORE and SYS_ADMIN, without privileged mode. On some hosts (Docker Desktop VMs, hardened kernels) that is not enough. Set `BEYLA_PRIVILEGED=1` in `.env` to use the privileged override, then run `make up`. Know the cost: that gives the container full host access. See `SECURITY.md`.
4. Kernel: eBPF needs Linux 5.8 or newer with BTF. Check `docker run --rm alpine uname -r`, and that `/sys/kernel/btf/vmlinux` exists in the VM. Also look at `perf_event_paranoid` and kernel lockdown.
5. Rootless Docker and Podman will not work.

macOS notes: Docker Desktop runs containers in a Linux VM. Beyla instruments processes inside that VM, not macOS. It often works with the capability set, and sometimes needs the privileged override. Colima and OrbStack kernels vary. Not yet verified on every setup. If it cannot work, leave Beyla failing: only `catalog` server spans are lost.

## Prometheus does not see new rules

Prometheus is started without the lifecycle API, so it does not reload. Rule files added after start are not seen. Restart it:

```
docker compose --profile lite restart prometheus
```

Then check http://localhost:9090/rules. Changes inside an existing file also need the restart. After editing `slo/storefront.yml`, run `make slo` first.

## Tempo is empty right after a restart

For a short time after Tempo restarts, search and the exemplar links can return nothing, even though traces were sent. Wait a minute and retry. Check readiness: `docker compose --profile lite --profile tools run --rm -T toolbox -fsS http://tempo:3200/ready`. While Tempo is down, the collector drops what it cannot send, so there is a gap. If the gap persists, check `OtelCollectorExportFailures`.

If you changed retention, note that in Tempo 3 it is `backend_worker.compaction.block_retention`, not the 2.x location.

## Alloy gets 403 from the socket proxy

The proxy only allows the API groups you enable. Alloy's `discovery.docker` needs both `CONTAINERS=1` and `NETWORKS=1` in the `docker-socket-proxy` environment. With only `CONTAINERS`, Alloy logs a 403 and no logs reach Loki. Check:

```
make logs S=alloy | grep -i "403\|forbidden"
docker compose --profile lite config | grep -A4 "docker-socket-proxy:" 
```

Also check that your service has the label `e2t.logs: "true"`, or Alloy will not pick it up.

## Docker Desktop memory

The lite profile uses about 1.5 GiB measured, with limits (caps, not usage) that add up to about 4.2 GiB. Docker Desktop needs at least 4 GiB. Raise it in Settings, Resources, then restart Docker. Signs of too little memory: containers exiting with code 137, `OOMKilled` true in `docker inspect`, `TargetDown` firing. See [sizing](sizing.md). macOS numbers are not yet measured.

## Other

- `make up` refuses to run: `.env` must not be world-readable. Fix with `chmod 600 .env`.
- Postgres login fails after regenerating `.env`: the password was set when the volume was created. Restore the old `.env`, or run `make clean` and `make up` (this deletes data).
- Grafana password: it is in `.env` as `GRAFANA_ADMIN_PASSWORD`. Anonymous viewers can look but not edit.
