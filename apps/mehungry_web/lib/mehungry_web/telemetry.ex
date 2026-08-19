defmodule MehungryWeb.Telemetry do
  @moduledoc """
  Telemetry supervisor for LiveDashboard.

  Defines the canonical metric set (`metrics/0`) rendered live by LiveDashboard
  at `/dashboard`, and starts the `:telemetry_poller`. The Prometheus scrape path
  is owned entirely by `MehungryWeb.PromEx` (served at the token-guarded
  `GET /metrics` — see `MehungryWeb.MetricsController`); this module no longer
  runs a Prometheus reporter.

  The bespoke DIY-observability layer (persistent snapshots, DIY error tracker,
  query-time profiles, process watchdog, custom VM/pool gauges) was removed; this
  is the minimal, standard baseline to build fresh on.
  """

  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("mehungry.repo.query.total_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.query_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.queue_time", unit: {:native, :millisecond}),

      # Oban Job Metrics
      summary("oban.job.stop.duration",
        tags: [:queue, :worker],
        tag_values: &oban_job_tags/1,
        unit: {:native, :millisecond}
      ),
      summary("oban.job.stop.queue_time",
        tags: [:queue, :worker],
        tag_values: &oban_job_tags/1,
        unit: {:native, :millisecond}
      ),
      counter("oban.job.exception.count",
        tags: [:queue, :worker],
        tag_values: &oban_job_tags/1
      ),

      # AI Agent Metrics (emitted by Mehungry.AI.{Agent, Client}; the Prometheus
      # scrape aggregates the same events via MehungryWeb.PromEx.AiPlugin).
      summary("mehungry.ai.agent.run.stop.duration",
        tags: [:agent, :outcome],
        unit: {:native, :millisecond}
      ),
      summary("mehungry.ai.agent.run.stop.iterations", tags: [:agent, :outcome]),
      summary("mehungry.ai.agent.tool.stop.duration",
        tags: [:agent, :tool, :status],
        unit: {:native, :millisecond}
      ),
      summary("mehungry.ai.client.request.stop.duration",
        tags: [:model, :status],
        unit: {:native, :millisecond}
      ),
      summary("mehungry.ai.client.request.stop.output_tokens", tags: [:model]),

      # VM Metrics (emitted by telemetry_poller's built-in measurements)
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp oban_job_tags(metadata) do
    job = metadata[:job] || %{}
    %{queue: Map.get(job, :queue), worker: Map.get(job, :worker)}
  end

  # VM metrics are emitted by the telemetry_poller application's own default
  # poller; no app-specific periodic measurements remain.
  defp periodic_measurements, do: []
end
