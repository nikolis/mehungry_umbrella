defmodule MehungryWeb.Telemetry do
  @moduledoc false

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
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),

      # Database Metrics
      summary("mehungry.repo.query.total_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.decode_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.query_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.queue_time", unit: {:native, :millisecond}),
      summary("mehungry.repo.query.idle_time", unit: {:native, :millisecond}),

      # Oban Job Metrics
      summary("oban.job.stop.duration",
        tags: [:queue, :worker],
        unit: {:native, :millisecond}
      ),
      summary("oban.job.stop.queue_time",
        tags: [:queue, :worker],
        unit: {:native, :millisecond}
      ),
      counter("oban.job.exception.count",
        tags: [:queue, :worker]
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Cachex Size Metrics (from periodic measurements)
      last_value("mehungry.cache.size", tags: [:cache]),

      # Oban Queue Depth (from periodic measurements)
      last_value("mehungry.oban.queue.depth", tags: [:queue])
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_cache_sizes, []},
      {__MODULE__, :emit_oban_queue_depths, []}
    ]
  end

  def emit_cache_sizes do
    for cache <- [:recipes_cache, :cache_user_tokens, :geo_cache] do
      case Cachex.size(cache) do
        {:ok, size} ->
          :telemetry.execute([:mehungry, :cache], %{size: size}, %{cache: cache})

        _ ->
          :ok
      end
    end
  end

  def emit_oban_queue_depths do
    import Ecto.Query

    depths =
      Mehungry.Repo.all(
        from j in Oban.Job,
          where: j.state == "available",
          group_by: j.queue,
          select: {j.queue, count(j.id)}
      )

    for {queue, depth} <- depths do
      :telemetry.execute([:mehungry, :oban, :queue], %{depth: depth}, %{queue: queue})
    end
  end
end
