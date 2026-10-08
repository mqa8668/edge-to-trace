# ADR-0010: Read-only Docker socket proxy

Status: Accepted

## Context

Alloy needs the Docker API to discover containers and read their logs. Mounting `/var/run/docker.sock` into a log agent is root-equivalent on the host. A security reviewer flags that first.

## Decision

Only one container touches the socket: `docker-socket-proxy` (Tecnativa), with the socket mounted read-only. It exposes only the API groups we enable: `CONTAINERS=1` and `NETWORKS=1`. Alloy talks to `tcp://docker-socket-proxy:2375` on the `obs` network, which publishes no port to the host.

Measured: with only `CONTAINERS=1`, `discovery.docker` fails with 403 because it also reads network details. `NETWORKS=1` is read-only like the rest.

## Consequences

- Alloy can read container metadata and logs, and cannot create, stop or exec into containers.
- A read-only mount does not make the socket harmless: the proxy can still read all container metadata, including environment variables. This is a reduction of risk, not removal.
- The proxy container does not use the shared hardening anchor (read-only root, `cap_drop: ALL`). It only has `no-new-privileges`. Tightening it is a possible follow-up.

## Alternatives considered

- Mount the socket directly into Alloy: simpler, and the exact thing reviewers flag.
- File-based log collection from `/var/lib/docker/containers`: needs a host path mount and loses Docker metadata, and it does not work the same on Docker Desktop.
