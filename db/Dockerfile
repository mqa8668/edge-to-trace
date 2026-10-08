# syntax=docker/dockerfile:1
# Postgres with the schema and seed baked in: no bind mounts, so it works on remote Docker contexts too.
FROM postgres:18.6-alpine@sha256:77f585114c32fbca283dc835b0596f4e52b51b4c6662d7810b2f4084f60a1873
COPY init/ /docker-entrypoint-initdb.d/
