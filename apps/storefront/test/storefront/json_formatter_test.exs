defmodule Storefront.JsonFormatterTest do
  use ExUnit.Case, async: true

  defp fmt(msg, meta) do
    event = %{level: :info, msg: msg, meta: Map.put(meta, :time, 1_700_000_000_000_000)}

    event
    |> Storefront.JsonFormatter.format(%{})
    |> IO.iodata_to_binary()
    |> String.trim()
    |> Jason.decode!()
  end

  test "emits the shared log shape with trace ids" do
    line =
      fmt({:string, "hello"}, %{
        otel_trace_id: ~c"4bf92f3577b34da6a3ce929d0e0e4736",
        otel_span_id: ~c"00f067aa0ba902b7"
      })

    assert %{"msg" => "hello", "level" => "info", "service" => "storefront"} = line
    assert line["trace_id"] == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert line["span_id"] == "00f067aa0ba902b7"
    assert is_binary(line["ts"])
  end

  test "flattens extra metadata and omits trace fields outside a span" do
    line = fmt({:string, "request"}, %{method: "GET", status: 200, pid: self()})
    assert line["method"] == "GET" and line["status"] == 200
    refute Map.has_key?(line, "trace_id")
    refute Map.has_key?(line, "pid")
  end

  test "handles format/args messages" do
    assert fmt({~c"n=~p", [3]}, %{})["msg"] == "n=3"
  end
end
