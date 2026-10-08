defmodule StorefrontWeb.Plugs.AccessLog do
  @moduledoc "One structured log line per request (health probes excluded). Runs inside the request span."
  @behaviour Plug
  require Logger

  @quiet ["/healthz", "/readyz"]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: path} = conn, _opts) when path in @quiet, do: conn

  def call(conn, _opts) do
    start = System.monotonic_time(:microsecond)

    Plug.Conn.register_before_send(conn, fn conn ->
      ms = Float.round((System.monotonic_time(:microsecond) - start) / 1000, 2)
      level = if conn.status >= 500, do: :error, else: :info

      Logger.log(level, "request",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: ms
      )

      conn
    end)
  end
end
