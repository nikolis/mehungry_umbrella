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

  # Emitted metric-name prefix for the Ecto plugin, e.g. "mehungry_web_prom_ex_ecto".
  # Derived from the same PromEx.metric_prefix/2 the Ecto plugin is configured with,
  # so the dashboard-var rewrite below can't drift from the emitted names.
  @ecto_metric_prefix PromEx.metric_prefix(:mehungry_web, :ecto) |> Enum.join("_")

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
      # The stock Ecto dashboard's `$repo` template variable is sourced from
      # `<prefix>_repo_init_status_info` — Ecto's one-shot repo-init telemetry.
      # In this umbrella that metric NEVER emits: `Mehungry.Repo` boots in the
      # `:mehungry` app before `:mehungry_web`/PromEx attach their handlers, so
      # the init event fires with nothing listening. With `$repo` empty, every
      # panel filters on `repo=""` and shows no data. Rewrite the variable at
      # upload time to source from the live query counter instead. See
      # `docs/infrastructure/observability.md`.
      {:prom_ex, "ecto.json", apply_function: &__MODULE__.fix_ecto_repo_var/1},
      {:prom_ex, "oban.json"}
    ]
  end

  @doc """
  Repoints the Ecto dashboard's `$repo` template variable off the never-emitted
  `_repo_init_status_info` metric onto the always-present query counter, so the
  variable resolves and the panels render. Applied by PromEx to the decoded
  dashboard before upload. Public because PromEx captures it by remote reference.
  """
  @spec fix_ecto_repo_var(map()) :: map()
  def fix_ecto_repo_var(dashboard) do
    query = "label_values(#{@ecto_metric_prefix}_repo_query_total_time_milliseconds_count, repo)"

    update_in(dashboard, ["templating", "list"], fn vars ->
      Enum.map(vars, fn
        %{"name" => "repo"} = var ->
          var |> Map.put("definition", query) |> Map.put("query", query)

        var ->
          var
      end)
    end)
  end
end
