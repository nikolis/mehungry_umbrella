defmodule Mehungry.Telemetry.SlowQueryLogger do
  require Logger

  # Queries taking longer than this are logged as warnings.
  @threshold_ms 500

  def attach do
    :telemetry.attach(
      "mehungry-slow-query-logger",
      [:mehungry, :repo, :query],
      &__MODULE__.handle_event/4,
      %{}
    )
  end

  def handle_event(_event, measurements, metadata, _config) do
    total_ms = System.convert_time_unit(measurements.total_time, :native, :millisecond)

    if total_ms >= @threshold_ms do
      Logger.warning(
        "[SlowQuery] #{total_ms}ms — #{inspect(metadata.query)} " <>
          "params=#{inspect(metadata.params)} " <>
          "source=#{inspect(metadata.source)}"
      )
    end
  end
end
