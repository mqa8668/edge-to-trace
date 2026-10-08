defmodule Storefront.JsonFormatter do
  @moduledoc """
  `:logger` formatter that emits one flat JSON object per line:
  `ts`, `level`, `msg`, `service`, plus `trace_id` / `span_id` from the OpenTelemetry logger
  metadata and any other Logger metadata (`method`, `path`, `status`, ...).
  """

  @drop [
    :pid,
    :gl,
    :time,
    :mfa,
    :file,
    :line,
    :domain,
    :error_logger,
    :report_cb,
    :otel_trace_id,
    :otel_span_id,
    :otel_trace_flags,
    :erl_level,
    :crash_reason
  ]

  def format(%{level: level, msg: msg, meta: meta}, _config) do
    base = %{
      ts: timestamp(meta),
      level: Atom.to_string(level),
      msg: message(msg),
      service: "storefront"
    }

    base
    |> put_trace(meta)
    |> Map.merge(extra(meta))
    |> Jason.encode_to_iodata!()
    |> then(&[&1, ?\n])
  rescue
    _ -> [~s({"level":"error","msg":"log formatting failed","service":"storefront"}), ?\n]
  end

  defp timestamp(%{time: t}), do: t |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()
  defp timestamp(_), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp message({:string, s}), do: IO.chardata_to_string(s)
  defp message({:report, report}), do: inspect(report)
  defp message({fmt, args}), do: fmt |> :io_lib.format(args) |> IO.chardata_to_string()

  defp put_trace(map, %{otel_trace_id: tid} = meta) when tid not in [nil, ""] do
    map
    |> Map.put(:trace_id, to_string(tid))
    |> Map.put(:span_id, to_string(Map.get(meta, :otel_span_id, "")))
  end

  defp put_trace(map, _), do: map

  defp extra(meta) do
    meta
    |> Map.drop(@drop)
    |> Map.new(fn {k, v} -> {k, encodable(v)} end)
  end

  defp encodable(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: v
  defp encodable(v) when is_atom(v), do: Atom.to_string(v)
  defp encodable(v), do: inspect(v)
end
