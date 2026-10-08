defmodule StorefrontWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :storefront

  plug StorefrontWeb.Plugs.AccessLog

  plug Plug.Parsers,
    parsers: [:json],
    pass: ["application/json"],
    json_decoder: Jason

  plug StorefrontWeb.Router
end
