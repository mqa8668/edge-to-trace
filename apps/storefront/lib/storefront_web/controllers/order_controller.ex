defmodule StorefrontWeb.OrderController do
  use StorefrontWeb, :controller
  require Logger

  alias Storefront.Clients

  def create(conn, %{"product_id" => pid, "quantity" => qty})
      when is_integer(pid) and pid > 0 and is_integer(qty) and qty > 0 and qty <= 100 do
    case Clients.reserve(pid, qty) do
      {:ok, _, order} ->
        conn |> put_status(201) |> json(%{order: order})

      {:error, {:status, 404, _}} ->
        conn |> put_status(404) |> json(%{error: "product not found"})

      {:error, {:status, 409, _}} ->
        conn |> put_status(409) |> json(%{error: "insufficient stock"})

      {:error, reason} ->
        Logger.error("reservation failed", error: inspect(reason))
        conn |> put_status(502) |> json(%{error: "catalog unavailable"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "product_id >= 1 and 1 <= quantity <= 100 required"})
  end
end
