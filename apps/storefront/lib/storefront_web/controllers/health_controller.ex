defmodule StorefrontWeb.HealthController do
  use StorefrontWeb, :controller

  def healthz(conn, _), do: json(conn, %{status: "ok"})

  def readyz(conn, _) do
    if Storefront.Clients.catalog_ready?() do
      json(conn, %{status: "ready"})
    else
      conn |> put_status(503) |> json(%{status: "catalog unavailable"})
    end
  end
end
