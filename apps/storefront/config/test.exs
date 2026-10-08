import Config

config :storefront, StorefrontWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  server: false,
  secret_key_base: String.duplicate("t", 64)

config :storefront,
  admin_port: nil,
  chaos_token: "test-token",
  catalog_req: [plug: {Req.Test, :catalog}, retry: false],
  recs_req: [plug: {Req.Test, :recs}, retry: false]

config :logger, level: :warning
config :opentelemetry, traces_exporter: :none
