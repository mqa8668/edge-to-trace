# ADR-0001: Record architecture decisions

Status: Accepted

## Context

edge-to-trace is a lab with many components. A reader who sees Tempo, Loki, Alloy, Beyla and an OpenTelemetry Collector in one repo will ask why each is there and what else was considered. Commit messages and chat history do not answer that well. A wiki would sit outside the repo and drift.

## Decision

We record each significant decision as a short Markdown file in `docs/adr/`, in MADR style: Status, Context, Decision, Consequences, Alternatives considered. Files are numbered and never renumbered. A decision that changes gets a new ADR that supersedes the old one, and the old one's status is updated.

ADRs 0001 to 0010 cover v0.1. Later milestones add their own (edge, SIEM, Kubernetes).

## Consequences

- Reviewers can read the reasoning next to the code that implements it.
- Every component has to earn a place. If an ADR is hard to write, the component probably should not be there.
- Writing ADRs costs a little time per decision.

## Alternatives considered

- Wiki or GitHub Discussions: invisible to someone who only clones the repo, and not versioned with the code.
- No record, rely on the README: the README says what exists, not why.
