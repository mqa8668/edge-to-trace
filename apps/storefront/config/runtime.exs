import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT", "8080"))

  config :storefront, StorefrontWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port],
    server: true,
    # API-only, no sessions: the key is never used to sign anything, but Phoenix wants one.
    secret_key_base: Base.encode64(:crypto.strong_rand_bytes(48))

  config :storefront,
    admin_port: String.to_integer(System.get_env("ADMIN_PORT", "9000")),
    chaos_token: System.get_env("CHAOS_TOKEN", ""),
    catalog_url: System.get_env("CATALOG_URL", "http://catalog:8081"),
    recs_url: System.get_env("RECS_URL", "http://recs:8082")
end
