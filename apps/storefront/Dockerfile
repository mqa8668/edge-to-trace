# syntax=docker/dockerfile:1
FROM hexpm/elixir:1.20.4-erlang-29.1.1-debian-trixie-20261005-slim@sha256:3f936c778234d0cce9d91dd61013cd2c830a215334bea598e4f5c666f8bb95bf AS base
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git \
 && rm -rf /var/lib/apt/lists/* \
 && mix local.hex --force && mix local.rebar --force
WORKDIR /app
COPY mix.exs mix.lock ./
COPY config config

FROM base AS test
ENV MIX_ENV=test
RUN mix deps.get && mix deps.compile
COPY lib lib
COPY test test
COPY .formatter.exs ./
RUN mix format --check-formatted && mix compile --warnings-as-errors && mix test

FROM base AS build
ENV MIX_ENV=prod
RUN mix deps.get --only prod && mix deps.compile
COPY lib lib
RUN mix release storefront

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin app
WORKDIR /app
COPY --from=build --chown=10001:10001 /app/_build/prod/rel/storefront ./
ENV RELEASE_DISTRIBUTION=none \
    RELEASE_TMP=/tmp \
    LANG=C.UTF-8 \
    OTEL_EXPORTER_OTLP_PROTOCOL=http_protobuf
USER 10001
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /healthz HTTP/1.0\\r\\n\\r\\n' >&3 && head -n1 <&3 | grep -q ' 200 '"]
CMD ["bin/storefront", "start"]
