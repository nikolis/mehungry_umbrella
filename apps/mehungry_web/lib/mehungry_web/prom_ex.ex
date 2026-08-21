defmodule MehungryWeb.PromEx do
  @moduledoc """
  PromEx supervisor — the single source of Prometheus metrics.

  Replaces the hand-rolled `TelemetryMetricsPrometheus.Core` reporter that used
  to live in `MehungryWeb.Telemetry`. PromEx attaches telemetry handlers for the
  standard plugin set below and aggregates them into the Prometheus text format,
  which is served by `MehungryWeb.MetricsController` at the token-guarded
  `GET /metrics` via `PromEx.get_metrics/1`.

  `MehungryWeb.Telemetry` is still the metric list for LiveDashboard's live
  charts (`metrics/0`); PromEx owns everything on the scrape path.

  Grafana dashboard upload and the standalone metrics HTTP server are disabled —
  we scrape through our own token-guarded endpoint. Configure with:

      config :mehungry_web, MehungryWeb.PromEx, disabled: false

  See `docs/infrastructure/observability.md`.
  """

  use PromEx, otp_app: :mehungry_web

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # BEAM/VM stats (memory, run queues, GC, schedulers).
      Plugins.Beam,
      # Application versions + dependency info for :mehungry_web.
      {Plugins.Application, otp_app: :mehungry_web},
      # HTTP request/response duration + counts, keyed by route.
      {Plugins.Phoenix, router: MehungryWeb.Router, endpoint: MehungryWeb.Endpoint},
      # LiveView mount/handle_event/handle_params durations.
      Plugins.PhoenixLiveView,
      # Ecto query total/queue/decode times for the core repo.
      #
      # `otp_app: :mehungry` is required so the plugin can resolve the repo's
      # config (it lives under the :mehungry app, not :mehungry_web). But
      # `otp_app` ALSO drives the emitted metric-name prefix, which would give
      # `mehungry_prom_ex_ecto_*` — whereas the bundled Grafana dashboard is
      # rendered from THIS module's otp_app (:mehungry_web) and queries
      # `mehungry_web_prom_ex_ecto_*`. Override the metric prefix so the emitted
      # names line up with the dashboard (and every other plugin here); without
      # this the Ecto dashboard shows no data.
      {Plugins.Ecto,
       otp_app: :mehungry,
       repos: [Mehungry.Repo],
       metric_prefix: PromEx.metric_prefix(:mehungry_web, :ecto)},
      # Oban job durations, queue times, and exception counts (default instance).
      {Plugins.Oban, oban_supervisors: [Oban]},
      # AI agent reliability + Anthropic API cost (custom — see AiPlugin).
      MehungryWeb.PromEx.AiPlugin
    ]
  end

  @impl true
  def dashboards do
    [
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "phoenix_live_view.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "oban.json"}
    ]
  end
end
