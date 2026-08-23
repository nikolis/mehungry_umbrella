defmodule MehungryWeb.MetricsController do
  @moduledoc """
  Prometheus scrape endpoint. `GET /metrics` renders every metric collected by
  `MehungryWeb.PromEx` in the Prometheus text exposition format, via
  `PromEx.get_metrics/1`.

  `GET /beam_scope/metrics` renders BeamScope's own Prometheus text exposition of
  the cluster model (`BeamScope.Exporter.Prometheus.scrape/0`). The BeamScope
  dashboard stays at `/beam_scope` behind session admin auth; only this scrape
  endpoint is token-guarded so a Prometheus job can reach it.

  Both endpoints are token-guarded by `MehungryWeb.Plugs.RequireMetricsToken`
  (see the router pipeline).
  """

  use MehungryWeb, :controller

  def index(conn, _params) do
    case PromEx.get_metrics(MehungryWeb.PromEx) do
      :prom_ex_down ->
        send_resp(conn, 503, "prom_ex_down")

      metrics ->
        conn
        |> put_resp_content_type("text/plain", "version=0.0.4")
        |> send_resp(200, metrics)
    end
  end

  def beam_scope(conn, _params) do
    conn
    |> put_resp_content_type("text/plain", "version=0.0.4")
    |> send_resp(200, BeamScope.Exporter.Prometheus.scrape())
  end
end
