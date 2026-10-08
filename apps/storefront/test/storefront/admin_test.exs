defmodule Storefront.AdminTest do
  use ExUnit.Case, async: false
  import Plug.Test
  import Plug.Conn

  setup do
    Storefront.Chaos.reset()
    :ok
  end

  defp call(method, body \\ nil, token \\ "test-token") do
    conn(method, "/admin/chaos", body && Jason.encode!(body))
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-chaos-token", token)
    |> Storefront.Admin.call(Storefront.Admin.init([]))
  end

  test "rejects missing or wrong token" do
    assert call(:get, nil, "nope").status == 403
    assert call(:get, nil, "").status == 403
  end

  test "set, read and reset roundtrip" do
    conn = call(:post, %{"error_ratio" => 1, "ttl_seconds" => 30})
    assert conn.status == 200
    assert %{"active" => true} = Jason.decode!(conn.resp_body)
    assert call(:get).status == 200
    assert %{"active" => false} = call(:delete).resp_body |> Jason.decode!()
  end

  test "invalid config is 422" do
    assert call(:post, %{"latency_ratio" => 7}).status == 422
  end
end
