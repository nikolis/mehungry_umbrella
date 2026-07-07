defmodule MehungryWeb.Telemetry do
  @moduledoc false

  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    # Required for :scheduler.utilization/2 sampling (emit_scheduler_utilization).
    :erlang.system_flag(:scheduler_wall_time, true)

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

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io"),

      # Cachex Size Metrics (from periodic measurements)
      last_value("mehungry.cache.size", tags: [:cache]),

      # Oban Queue Depth (from periodic measurements)
      last_value("mehungry.oban.queue.depth", tags: [:queue]),

      # Process watchdog (from periodic measurements)
      last_value("mehungry.vm.process.max_message_queue"),
      last_value("mehungry.vm.process.over_threshold_count"),

      # Scheduler utilization in percent (from periodic measurements)
      last_value("mehungry.vm.scheduler.utilization"),
      last_value("mehungry.vm.scheduler.weighted"),

      # Concurrent LiveView connections (from periodic measurements)
      last_value("mehungry.vm.live_view.count"),

      # DB connection pool utilization (from periodic measurements)
      last_value("mehungry.repo.pool.busy"),
      last_value("mehungry.repo.pool.total"),
      last_value("mehungry.repo.pool.pool_size")
    ]
  end

  defp oban_job_tags(metadata) do
    job = metadata[:job] || %{}
    %{queue: Map.get(job, :queue), worker: Map.get(job, :worker)}
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_cache_sizes, []},
      {__MODULE__, :emit_oban_queue_depths, []},
      {__MODULE__, :emit_process_stats, []},
      {__MODULE__, :emit_scheduler_utilization, []},
      {__MODULE__, :emit_pool_stats, []}
    ]
  end

  # Utilization is computed between consecutive poller runs (~10s window) by
  # diffing :scheduler samples; the previous sample is kept in :persistent_term.
  # The first run only stores a baseline and emits nothing.
  def emit_scheduler_utilization do
    key = {__MODULE__, :scheduler_sample}
    current = :scheduler.sample_all()

    case :persistent_term.get(key, nil) do
      nil ->
        :ok

      previous ->
        util = :scheduler.utilization(previous, current)
        {:total, total, _} = List.keyfind(util, :total, 0)
        {:weighted, weighted, _} = List.keyfind(util, :weighted, 0)

        :telemetry.execute(
          [:mehungry, :vm, :scheduler],
          %{utilization: total * 100.0, weighted: weighted * 100.0},
          %{}
        )
    end

    :persistent_term.put(key, current)
    :ok
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

  # Any process whose mailbox exceeds this is considered stuck/overloaded.
  @message_queue_threshold 1_000

  def emit_process_stats do
    {max_queue, offenders, live_view_count} =
      Enum.reduce(Process.list(), {0, [], 0}, fn pid, {acc_max, acc_offenders, acc_lv} ->
        acc_lv =
          case :proc_lib.translate_initial_call(pid) do
            {_mod, :mount, 3} -> acc_lv + 1
            _ -> acc_lv
          end

        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} when len >= @message_queue_threshold ->
            {max(acc_max, len), [pid | acc_offenders], acc_lv}

          {:message_queue_len, len} ->
            {max(acc_max, len), acc_offenders, acc_lv}

          nil ->
            {acc_max, acc_offenders, acc_lv}
        end
      end)

    :telemetry.execute(
      [:mehungry, :vm, :process],
      %{max_message_queue: max_queue, over_threshold_count: length(offenders)},
      %{}
    )

    :telemetry.execute([:mehungry, :vm, :live_view], %{count: live_view_count}, %{})

    for pid <- offenders do
      info =
        Process.info(pid, [
          :registered_name,
          :initial_call,
          :current_function,
          :message_queue_len
        ])

      Logger.warning(
        "[ProcessWatchdog] Mailbox over #{@message_queue_threshold}: #{inspect(pid)} #{inspect(info)}"
      )
    end

    :ok
  end

  def emit_oban_queue_depths do
    import Ecto.Query

    depths =
      Mehungry.Repo.all(
        from(j in Oban.Job,
          where: j.state == "available",
          group_by: j.queue,
          select: {j.queue, count(j.id)}
        )
      )

    for {queue, depth} <- depths do
      :telemetry.execute([:mehungry, :oban, :queue], %{depth: depth}, %{queue: queue})
    end
  end

  # Approximates DB pool utilization by counting connections to the database
  # itself via pg_stat_activity (same technique ecto_psql_extras uses), since
  # DBConnection doesn't expose a simple busy/idle count for the Ecto pool.
  # Assumes the database is single-tenant for this app.
  def emit_pool_stats do
    pool_size = Keyword.get(Mehungry.Repo.config(), :pool_size, 10)

    sql = """
    SELECT count(*) FILTER (WHERE state = 'active') AS busy, count(*) AS total
    FROM pg_stat_activity WHERE datname = current_database()
    """

    case Ecto.Adapters.SQL.query(Mehungry.Repo, sql, []) do
      {:ok, %{rows: [[busy, total]]}} ->
        :telemetry.execute(
          [:mehungry, :repo, :pool],
          %{busy: busy, total: total, pool_size: pool_size},
          %{}
        )

      _ ->
        :ok
    end
  end
end
