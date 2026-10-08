defmodule Storefront.ChaosTest do
  use ExUnit.Case, async: true

  alias Storefront.Chaos

  defp start_chaos(rolls) do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    {:ok, queue} = Agent.start_link(fn -> rolls end)

    rand = fn -> Agent.get_and_update(queue, fn [h | t] -> {h, t} end) end
    now = fn -> Agent.get(clock, & &1) end
    pid = start_supervised!({Chaos, name: nil, now: now, rand: rand}, id: make_ref())
    {pid, clock}
  end

  test "inactive chaos is a no-op and consumes no randomness" do
    {c, _} = start_chaos([])
    assert Chaos.decide(c) == {0, false}
    refute Chaos.state(c).active
  end

  test "latency and error ratios use two independent rolls" do
    {c, _} = start_chaos([0.1, 0.9, 0.9, 0.1])

    {:ok, _} =
      Chaos.set(c, %{
        "latency_ms" => 800,
        "latency_ratio" => 0.6,
        "error_ratio" => 0.25,
        "ttl_seconds" => 60
      })

    assert Chaos.decide(c) == {800, false}
    assert Chaos.decide(c) == {0, true}
  end

  test "chaos expires after its ttl" do
    {c, clock} = start_chaos([])
    {:ok, _} = Chaos.set(c, %{"error_ratio" => 1, "ttl_seconds" => 30})
    assert Chaos.state(c).active
    Agent.update(clock, fn _ -> 31_000 end)
    refute Chaos.state(c).active
    assert Chaos.decide(c) == {0, false}
  end

  test "default ttl is applied and out-of-range values are rejected" do
    {c, _} = start_chaos([])
    {:ok, state} = Chaos.set(c, %{"error_ratio" => 1})
    assert state.config.ttl_seconds == 900

    assert {:error, _} = Chaos.set(c, %{"latency_ms" => -1})
    assert {:error, _} = Chaos.set(c, %{"latency_ratio" => 1.5})
    assert {:error, _} = Chaos.set(c, %{"ttl_seconds" => 3601})
    assert {:error, _} = Chaos.set(c, %{"bogus" => 1})
  end

  test "reset turns chaos off" do
    {c, _} = start_chaos([])
    {:ok, _} = Chaos.set(c, %{"error_ratio" => 1})
    refute Chaos.reset(c).active
  end
end
