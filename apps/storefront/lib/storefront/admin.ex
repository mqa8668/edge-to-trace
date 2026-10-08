defmodule Storefront.Admin do
  @moduledoc """
  Chaos control API on the internal admin port. Requires the `X-Chaos-Token` header;
  an empty configured token disables the API entirely.
  """
  use Plug.Router

  plug :authenticate
  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason, pass: ["application/json"]
  plug :dispatch

  get "/admin/chaos" do
    send_json(conn, 200, Storefront.Chaos.state())
  end

  post "/admin/chaos" do
    case Storefront.Chaos.set(conn.body_params) do
      {:ok, state} -> send_json(conn, 200, state)
      {:error, msg} -> send_json(conn, 422, %{error: msg})
    end
  end

  delete "/admin/chaos" do
    send_json(conn, 200, Storefront.Chaos.reset())
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp authenticate(conn, _opts) do
    expected = Application.get_env(:storefront, :chaos_token, "")
    got = conn |> get_req_header("x-chaos-token") |> List.first("")

    if expected != "" and Plug.Crypto.secure_compare(expected, got) do
      conn
    else
      conn |> send_json(403, %{error: "forbidden"}) |> halt()
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end
end
