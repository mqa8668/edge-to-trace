# ADR-0002: Docker Compose with profiles as the runtime

Status: Accepted

## Context

The lab must start with one command on a laptop and in a CI runner. The observability story (SLO alert, exemplar, trace, logs) is the point. Cluster plumbing would hide it. Later milestones add an edge tier, a SIEM and Kubernetes, and these must not make the first run heavier.

## Decision

Use Docker Compose for v0.1 to v0.3. Every service in `compose.yaml` carries a profile. v0.1 ships only `lite`. Later profiles (`edge`, `full`) are planned as additions to it, so `lite` stays small. A `tools` profile holds a helper `toolbox` container (curl) used by scripts to reach internal ports without publishing them. Kubernetes arrives in v0.4 as a separate path.

Common hardening is shared through a YAML anchor: `no-new-privileges`, `cap_drop: [ALL]`, read-only root filesystem, `restart: unless-stopped`. Two networks, `app` and `obs`, separate the demo services from the observability tier.

## Consequences

- `make up` works on any machine with Docker and Compose v2.
- Memory limits are set per service (see `docs/sizing.md`).
- Compose has no network policies. The `app` and `obs` split is coarse, and v0.4 replaces it with real policies.
- Profiles must be passed on every compose call; the Makefile does this.

## Alternatives considered

- Kubernetes first (kind, k3d): higher entry cost, and the first screen a visitor sees would be pods, not traces.
- Plain compose without profiles: every later milestone would make the default stack heavier.
