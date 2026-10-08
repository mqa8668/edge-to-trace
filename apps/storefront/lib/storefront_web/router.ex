defmodule StorefrontWeb.Router do
  use StorefrontWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug StorefrontWeb.Plugs.Chaos
  end

  # Health probes: no chaos, no auth.
  scope "/", StorefrontWeb do
    get "/healthz", HealthController, :healthz
    get "/readyz", HealthController, :readyz
  end

  scope "/api", StorefrontWeb do
    pipe_through :api

    get "/products/:id", ProductController, :show
    post "/orders", OrderController, :create
  end
end
