defmodule StorefrontWeb.Plugs.Chaos do
  @moduledoc "Applies injected latency and 503s to API requests."
  @behaviour Plug
  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case Storefront.Chaos.decide() do
      {0, false} ->
        conn

      {delay, fail?} ->
        if delay > 0, do: Process.sleep(delay)

        if fail? do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(503, Jason.encode!(%{error: "chaos: injected failure"}))
          |> halt()
        else
          conn
        end
    end
  end
end
