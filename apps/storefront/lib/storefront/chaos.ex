defmodule Storefront.Chaos do
  @moduledoc """
  Runtime fault injection (latency and 503s) with a TTL so a forgotten demo heals itself.

  Time and randomness are injectable (`:now` in milliseconds, `:rand` returning a float in [0, 1))
  so the ratio and TTL logic can be tested without sleeping.
  """
  use Agent

  @default_ttl 900
  @max_ttl 3600
  @off %{latency_ms: 0, latency_ratio: 0.0, error_ratio: 0.0, ttl_seconds: 0}

  def start_link(opts) do
    now = Keyword.get(opts, :now, fn -> System.monotonic_time(:millisecond) end)
    rand = Keyword.get(opts, :rand, &:rand.uniform/0)
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{cfg: @off, expires: nil, now: now, rand: rand} end, name: name)
  end

  @doc "Validate and apply a config map with string keys. Out-of-range values are rejected, never clamped."
  def set(server \\ __MODULE__, params) when is_map(params) do
    with {:ok, cfg} <- validate(params) do
      ttl = if cfg.ttl_seconds == 0, do: @default_ttl, else: cfg.ttl_seconds
      cfg = %{cfg | ttl_seconds: ttl}

      Agent.update(server, fn s -> %{s | cfg: cfg, expires: s.now.() + ttl * 1000} end)
      {:ok, state(server)}
    end
  end

  def reset(server \\ __MODULE__) do
    Agent.update(server, fn s -> %{s | cfg: @off, expires: nil} end)
    state(server)
  end

  def state(server \\ __MODULE__) do
    Agent.get(server, fn s ->
      if active?(s) do
        %{active: true, config: s.cfg, remaining_seconds: div(s.expires - s.now.(), 1000)}
      else
        %{active: false, config: @off, remaining_seconds: 0}
      end
    end)
  end

  @doc "Returns `{delay_ms, fail?}`. Two independent rolls: latency first, then error."
  def decide(server \\ __MODULE__) do
    Agent.get(server, fn s ->
      if active?(s) do
        cfg = s.cfg

        delay =
          if cfg.latency_ms > 0 and s.rand.() < cfg.latency_ratio, do: cfg.latency_ms, else: 0

        fail? = cfg.error_ratio > 0 and s.rand.() < cfg.error_ratio
        {delay, fail?}
      else
        {0, false}
      end
    end)
  end

  defp active?(%{expires: nil}), do: false
  defp active?(%{expires: expires, now: now}), do: now.() < expires

  @allowed ~w(latency_ms latency_ratio error_ratio ttl_seconds)

  defp validate(params) do
    with :ok <- known_keys(params),
         {:ok, latency_ms} <- int(params, "latency_ms", 0, 60_000),
         {:ok, latency_ratio} <- ratio(params, "latency_ratio"),
         {:ok, error_ratio} <- ratio(params, "error_ratio"),
         {:ok, ttl} <- int(params, "ttl_seconds", 0, @max_ttl) do
      {:ok,
       %{
         latency_ms: latency_ms,
         latency_ratio: latency_ratio,
         error_ratio: error_ratio,
         ttl_seconds: ttl
       }}
    end
  end

  defp known_keys(params) do
    case Map.keys(params) -- @allowed do
      [] -> :ok
      extra -> {:error, "unknown field(s): #{Enum.join(extra, ", ")}"}
    end
  end

  defp int(params, key, min, max) do
    case Map.get(params, key, 0) do
      v when is_integer(v) and v >= min and v <= max -> {:ok, v}
      _ -> {:error, "#{key} must be an integer between #{min} and #{max}"}
    end
  end

  defp ratio(params, key) do
    case Map.get(params, key, 0.0) do
      v when is_number(v) and v >= 0 and v <= 1 -> {:ok, v * 1.0}
      _ -> {:error, "#{key} must be a number between 0 and 1"}
    end
  end
end
