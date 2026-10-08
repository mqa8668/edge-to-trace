defmodule Storefront.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)

    children =
      [
        {Storefront.Chaos, name: Storefront.Chaos},
        StorefrontWeb.Endpoint
      ] ++ admin_children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Storefront.Supervisor)
  end

  # The chaos admin API lives on its own internal port and is never published by compose.
  defp admin_children do
    case Application.get_env(:storefront, :admin_port) do
      nil -> []
      port -> [{Bandit, plug: Storefront.Admin, scheme: :http, ip: {0, 0, 0, 0}, port: port}]
    end
  end
end
