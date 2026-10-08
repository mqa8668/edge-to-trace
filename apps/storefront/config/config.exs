import Config

config :storefront, StorefrontWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: StorefrontWeb.ErrorJSON], layout: false]

config :phoenix, :json_library, Jason

# One JSON object per line: ts, level, msg, service, trace_id, span_id (see docs/architecture.md).
config :logger, :default_handler, formatter: {Storefront.JsonFormatter, %{}}
config :logger, level: :info

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

# Endpoint, headers and resource attributes come from the standard OTEL_* environment variables.
config :opentelemetry_exporter, otlp_protocol: :http_protobuf

import_config "#{config_env()}.exs"
