# PostgresDown

Severity: page. Fires when `pg_up == 0` for 1 minute.

## What it means

The `postgres-exporter` cannot connect to Postgres. Either Postgres is down, or the exporter cannot reach it or log in.

## Impact

`catalog` depends on Postgres, so product reads and orders fail, which burns the availability SLO. Alertmanager inhibits the ticket variant of `StorefrontAvailabilityBurn` while this alert fires, because this is the cause and that is the symptom.

## First 5 minutes

1. `docker compose --profile lite ps postgres postgres-exporter`.
2. `make logs S=postgres | tail -50`.
3. Readiness: `docker compose --profile lite exec postgres pg_isready -U acme -d acme -h 127.0.0.1`.
4. Query: `pg_up`, and `up{job="postgres-exporter"}`. If `up` is 0 too, the exporter itself is the problem (see `target-down.md`).
5. Impact check: http://localhost:3000/d/e2t-slo?var-slo=availability and the catalog panel in http://localhost:3000/d/e2t-service?var-service=catalog.

## Likely causes

- Postgres crashed or was OOM-killed (limit is 256m).
- Disk full on the `pgdata` volume.
- Password mismatch between `.env` and the existing volume, after `.env` was regenerated. The password is only applied when the volume is first created.
- Slow start after a restart.

## Mitigation

- Restart: `docker compose --profile lite up -d postgres`.
- Password mismatch: restore the old `.env`, or reset the lab data with `make clean` (this deletes all volumes) and `make up`.
- Raise `mem_limit` if the container is OOM-killed.

## Follow-up

- There is no migration framework or backup in the lab. Data loss on `make clean` is expected and the seed data is rebuilt on start.
- Confirm `pg_up` is 1 and the availability burn clears.
