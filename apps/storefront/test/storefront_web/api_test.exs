defmodule StorefrontWeb.ApiTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn

  @endpoint StorefrontWeb.Endpoint
  @product %{"id" => 1, "title" => "The Quiet Harbor", "stock" => 5}

  setup do
    Storefront.Chaos.reset()
    :ok
  end

  defp stub_catalog(fun), do: Req.Test.stub(:catalog, fun)
  defp stub_recs(fun), do: Req.Test.stub(:recs, fun)

  defp happy_catalog do
    stub_catalog(fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/products/1"} ->
          Req.Test.json(conn, @product)

        {"GET", "/products/2"} ->
          conn |> put_status(404) |> Req.Test.json(%{error: "nope"})

        {"GET", "/readyz"} ->
          Req.Test.json(conn, %{status: "ready"})

        {"POST", "/reservations"} ->
          conn |> put_status(201) |> Req.Test.json(%{order_id: 7, stock_left: 3})
      end
    end)
  end

  test "product view merges catalog and recs" do
    happy_catalog()
    stub_recs(fn conn -> Req.Test.json(conn, %{"recommendations" => [%{"id" => 3}]}) end)

    body = build_conn() |> get("/api/products/1") |> json_response(200)
    assert body["product"] == @product
    assert body["recommendations"] == [%{"id" => 3}]
    assert body["degraded"] == false
  end

  test "recs failure degrades to an empty list" do
    happy_catalog()
    stub_recs(fn conn -> conn |> put_status(503) |> Req.Test.json(%{error: "down"}) end)

    body = build_conn() |> get("/api/products/1") |> json_response(200)
    assert body["recommendations"] == []
    assert body["degraded"] == true
  end

  test "recs timeout degrades instead of failing" do
    happy_catalog()
    stub_recs(fn conn -> Req.Test.transport_error(conn, :timeout) end)

    body = build_conn() |> get("/api/products/1") |> json_response(200)
    assert body["degraded"] == true
  end

  test "catalog 404 is 404, catalog failure is 502, bad id is 400" do
    happy_catalog()
    stub_recs(fn conn -> Req.Test.json(conn, %{"recommendations" => []}) end)
    assert build_conn() |> get("/api/products/2") |> json_response(404)
    assert build_conn() |> get("/api/products/abc") |> json_response(400)

    stub_catalog(fn conn -> conn |> put_status(500) |> Req.Test.json(%{}) end)
    assert build_conn() |> get("/api/products/1") |> json_response(502)
  end

  test "orders: success, validation and conflict" do
    happy_catalog()

    assert build_conn()
           |> post("/api/orders", %{product_id: 1, quantity: 2})
           |> json_response(201)

    assert build_conn()
           |> post("/api/orders", %{product_id: 1, quantity: 0})
           |> json_response(400)

    stub_catalog(fn conn ->
      conn |> put_status(409) |> Req.Test.json(%{error: "insufficient stock"})
    end)

    assert build_conn()
           |> post("/api/orders", %{product_id: 1, quantity: 2})
           |> json_response(409)
  end

  test "health: healthz always ok, readyz follows catalog" do
    happy_catalog()
    assert build_conn() |> get("/healthz") |> json_response(200)
    assert build_conn() |> get("/readyz") |> json_response(200)
    stub_catalog(fn conn -> conn |> put_status(503) |> Req.Test.json(%{}) end)
    assert build_conn() |> get("/readyz") |> json_response(503)
  end

  test "injected errors return 503 on the API but never on health probes" do
    happy_catalog()
    {:ok, _} = Storefront.Chaos.set(%{"error_ratio" => 1, "ttl_seconds" => 30})
    assert build_conn() |> get("/api/products/1") |> json_response(503)
    assert build_conn() |> get("/healthz") |> json_response(200)
  end
end
