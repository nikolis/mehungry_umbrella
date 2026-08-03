defmodule MehungryWeb.Api.LocalAi.MetricsController do
  @moduledoc """
  Requests-per-minute for the LocalAi REST API itself, so the non-deployed
  `mehungry_local_ai` service (or an operator holding the shared token) can
  poll its own call rate. Token-guarded like the rest of `/api/local_ai/*`.

  `GET /api/local_ai/metrics?window_seconds=3600` — window defaults to 1h and
  is clamped to `[60, 604_800]`.
  """

  use MehungryWeb, :controller

  alias Mehungry.Telemetry.RequestRate

  def index(conn, params) do
    window = parse_window(params["window_seconds"], 3600)
    json(conn, RequestRate.local_ai(window))
  end

  defp parse_window(nil, default), do: default

  defp parse_window(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} -> n |> max(60) |> min(604_800)
      :error -> default
    end
  end
end
