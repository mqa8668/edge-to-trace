defmodule StorefrontWeb.ProductController do
  use StorefrontWeb, :controller
  alias OpenTelemetry.Tracer

  alias Storefront.Clients

  def show(conn, %{"id" => raw_id}) do
    case Integer.parse(raw_id) do
      {id, ""} when id > 0 -> show_product(conn, id)
      _ -> conn |> put_status(400) |> json(%{error: "invalid product id"})
    end
  end

  defp show_product(conn, id) do
    # Fan out in parallel; carry the trace context into the tasks so client spans are children.
    ctx = OpenTelemetry.Ctx.get_current()

    catalog =
      Task.async(fn ->
        OpenTelemetry.Ctx.attach(ctx)
        Clients.get_product(id)
      end)

    recs =
      Task.async(fn ->
        OpenTelemetry.Ctx.attach(ctx)
        Clients.recommendations(id)
      end)

    catalog_res = Task.await(catalog, 5_000)
    recs_res = Task.await(recs, 5_000)

    case catalog_res do
      {:ok, _, product} ->
        {recommendations, degraded?} = recommendations(recs_res)
        Tracer.set_attribute(:"recs.degraded", degraded?)
        json(conn, %{product: product, recommendations: recommendations, degraded: degraded?})

      {:error, {:status, 404, _}} ->
        conn |> put_status(404) |> json(%{error: "product not found"})

      {:error, reason} ->
        require Logger
        Logger.error("catalog call failed", error: inspect(reason))
        conn |> put_status(502) |> json(%{error: "catalog unavailable"})
    end
  end

  # recs is optional: any failure or timeout degrades to an empty list.
  defp recommendations({:ok, _, %{"recommendations" => list}}) when is_list(list),
    do: {list, false}

  defp recommendations(other) do
    require Logger
    Logger.warning("recs degraded", reason: inspect(other))
    {[], true}
  end
end
