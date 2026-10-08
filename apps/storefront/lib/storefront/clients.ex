defmodule Storefront.Clients do
  @moduledoc """
  Outgoing HTTP to catalog and recs. Req + opentelemetry_req gives client spans and
  W3C `traceparent` propagation without any manual header handling.
  """

  @catalog_timeout 2_000
  @recs_timeout 400

  def get_product(id), do: catalog() |> Req.get(url: "/products/#{id}") |> result()

  def reserve(product_id, quantity),
    do:
      catalog()
      |> Req.post(url: "/reservations", json: %{product_id: product_id, quantity: quantity})
      |> result()

  def recommendations(product_id),
    do: recs() |> Req.get(url: "/recommendations", params: [product_id: product_id]) |> result()

  def catalog_ready? do
    match?({:ok, _, _}, catalog() |> Req.get(url: "/readyz", receive_timeout: 300) |> result())
  end

  defp catalog,
    do:
      client(:catalog_url, :catalog_req, "http://catalog:8081", receive_timeout: @catalog_timeout)

  defp recs, do: client(:recs_url, :recs_req, "http://recs:8082", receive_timeout: @recs_timeout)

  defp client(url_key, opts_key, default_url, defaults) do
    base = Application.get_env(:storefront, url_key, default_url)
    extra = Application.get_env(:storefront, opts_key, [])

    [base_url: base, retry: false, connect_options: [timeout: 400]]
    |> Keyword.merge(defaults)
    |> Keyword.merge(extra)
    |> Req.new()
    |> OpentelemetryReq.attach(propagate_trace_headers: true)
  end

  defp result({:ok, %Req.Response{status: s, body: body}}) when s in 200..299, do: {:ok, s, body}
  defp result({:ok, %Req.Response{status: s, body: body}}), do: {:error, {:status, s, body}}
  defp result({:error, reason}), do: {:error, {:transport, reason}}
end
