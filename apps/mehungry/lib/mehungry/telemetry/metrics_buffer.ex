defmodule Mehungry.Telemetry.MetricsBuffer do
  use GenServer
  require Logger
  import Ecto.Query

  @table __MODULE__
  @query_table Module.concat(__MODULE__, QueryTimes)
  @timeline_table Module.concat(__MODULE__, QueryTimeline)
  @flush_interval :timer.minutes(5)
  @query_text_limit 1_000
  @timeline_retention :timer.minutes(60)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:public, :named_table, :duplicate_bag])
    :ets.new(@query_table, [:public, :named_table, :duplicate_bag])
    :ets.new(@timeline_table, [:public, :named_table, :ordered_set])
    attach_handlers()
    schedule_flush()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:flush, state) do
    flush()
    flush_queries()
    trim_timeline()
    schedule_flush()
    {:noreply, state}
  end

  # --- Telemetry handlers ---

  def handle_repo_query(_event, measurements, metadata, _config) do
    source = metadata[:source] || "unknown"

    with q_time when is_integer(q_time) <- measurements[:query_time] do
      duration_ms = to_ms(q_time)
      record_query(source, metadata[:query], duration_ms)
      record_timeline_event(source, metadata[:query], duration_ms)
    end

    with total when is_integer(total) <- measurements[:total_time] do
      record("mehungry.repo.query.total_time", %{source: source}, to_ms(total))
    end

    with queue_time when is_integer(queue_time) <- measurements[:queue_time] do
      record("mehungry.repo.query.queue_time", %{source: source}, to_ms(queue_time))
    end
  end

  def handle_router_dispatch(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      record("phoenix.request.duration", %{route: metadata[:route] || "unknown"}, to_ms(duration))
    end
  end

  def handle_live_view_mount(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      record("live_view.mount.duration", %{view: view_name(metadata)}, to_ms(duration))
    end
  end

  def handle_live_view_event(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      tags = %{view: view_name(metadata), event: to_string(metadata[:event] || "unknown")}
      record("live_view.handle_event.duration", tags, to_ms(duration))
    end
  end

  def handle_oban_job_stop(_event, measurements, metadata, _config) do
    tags = oban_job_tags(metadata)

    with duration when is_integer(duration) <- measurements[:duration] do
      record("oban.job.duration", tags, to_ms(duration))
    end

    with queue_time when is_integer(queue_time) <- measurements[:queue_time] do
      record("oban.job.queue_time", tags, to_ms(queue_time))
    end
  end

  def handle_oban_job_exception(_event, _measurements, metadata, _config) do
    record("oban.job.exception.count", oban_job_tags(metadata), 1.0)
  end

  def handle_cache_size(_event, measurements, metadata, _config) do
    with size when is_integer(size) <- measurements[:size] do
      record("mehungry.cache.size", %{cache: to_string(metadata[:cache])}, size * 1.0)
    end
  end

  def handle_oban_queue_depth(_event, measurements, metadata, _config) do
    with depth when is_integer(depth) <- measurements[:depth] do
      record("mehungry.oban.queue.depth", %{queue: to_string(metadata[:queue])}, depth * 1.0)
    end
  end

  def handle_vm_process_stats(_event, measurements, _metadata, _config) do
    record("mehungry.vm.process.max_message_queue", %{}, (measurements[:max_message_queue] || 0) * 1.0)

    record(
      "mehungry.vm.process.over_threshold_count",
      %{},
      (measurements[:over_threshold_count] || 0) * 1.0
    )
  end

  def handle_vm_scheduler(_event, measurements, _metadata, _config) do
    with utilization when is_number(utilization) <- measurements[:utilization] do
      record("mehungry.vm.scheduler.utilization", %{}, utilization * 1.0)
    end

    with weighted when is_number(weighted) <- measurements[:weighted] do
      record("mehungry.vm.scheduler.weighted", %{}, weighted * 1.0)
    end
  end

  def handle_vm_memory(_event, measurements, _metadata, _config) do
    with total when is_integer(total) <- measurements[:total] do
      record("vm.memory.total", %{}, total / 1024.0)
    end
  end

  def handle_vm_live_view_count(_event, measurements, _metadata, _config) do
    with count when is_integer(count) <- measurements[:count] do
      record("mehungry.vm.live_view.count", %{}, count * 1.0)
    end
  end

  def handle_repo_pool_stats(_event, measurements, _metadata, _config) do
    record("mehungry.repo.pool.busy", %{}, (measurements[:busy] || 0) * 1.0)
    record("mehungry.repo.pool.total", %{}, (measurements[:total] || 0) * 1.0)
    record("mehungry.repo.pool.pool_size", %{}, (measurements[:pool_size] || 0) * 1.0)
  end

  # --- Private ---

  defp attach_handlers do
    handlers = [
      {"buffer-repo-query", [:mehungry, :repo, :query], &handle_repo_query/4},
      {"buffer-router-dispatch", [:phoenix, :router_dispatch, :stop], &handle_router_dispatch/4},
      {"buffer-lv-mount", [:phoenix, :live_view, :mount, :stop], &handle_live_view_mount/4},
      {"buffer-lv-event", [:phoenix, :live_view, :handle_event, :stop], &handle_live_view_event/4},
      {"buffer-oban-job-stop", [:oban, :job, :stop], &handle_oban_job_stop/4},
      {"buffer-oban-job-exception", [:oban, :job, :exception], &handle_oban_job_exception/4},
      {"buffer-cache-size", [:mehungry, :cache], &handle_cache_size/4},
      {"buffer-oban-queue-depth", [:mehungry, :oban, :queue], &handle_oban_queue_depth/4},
      {"buffer-vm-process", [:mehungry, :vm, :process], &handle_vm_process_stats/4},
      {"buffer-vm-scheduler", [:mehungry, :vm, :scheduler], &handle_vm_scheduler/4},
      {"buffer-vm-memory", [:vm, :memory], &handle_vm_memory/4},
      {"buffer-vm-live-view-count", [:mehungry, :vm, :live_view], &handle_vm_live_view_count/4},
      {"buffer-repo-pool", [:mehungry, :repo, :pool], &handle_repo_pool_stats/4}
    ]

    for {id, event, handler} <- handlers do
      case :telemetry.attach(id, event, handler, %{}) do
        :ok -> :ok
        {:error, :already_exists} -> :ok
      end
    end
  end

  defp flush do
    entries = :ets.tab2list(@table)
    :ets.delete_all_objects(@table)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      entries
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.map(fn {{metric, tags}, kv_list} ->
        values = Enum.map(kv_list, &elem(&1, 1)) |> Enum.sort()
        count = length(values)
        p95_idx = max(0, ceil(0.95 * count) - 1)

        %{
          metric: metric,
          tags: tags,
          period_start: now,
          min: List.first(values),
          max: List.last(values),
          avg: Enum.sum(values) / count,
          p95: Enum.at(values, p95_idx),
          sample_count: count
        }
      end)

    if rows != [] do
      Mehungry.Repo.insert_all(Mehungry.Telemetry.Snapshot, rows)
    end
  rescue
    e -> Logger.error("[MetricsBuffer] Flush failed: #{inspect(e)}")
  end

  defp record(metric, tags, value) do
    try do
      :ets.insert(@table, {{metric, tags}, value})
    catch
      :error, :badarg -> :ok
    end
  end

  # Groups query_time samples by a fingerprint of the query shape (source +
  # SQL text) rather than by source alone, so each row on the Queries
  # dashboard page can be traced back to the exact statement that produced it.
  defp record_query(source, query, value) do
    query_text = (query || "unknown") |> to_string() |> String.slice(0, @query_text_limit)
    fingerprint = fingerprint_query(source, query_text)

    try do
      :ets.insert(@query_table, {fingerprint, {value, query_text, source}})
    catch
      :error, :badarg -> :ok
    end
  end

  defp fingerprint_query(source, query_text) do
    :crypto.hash(:sha256, "#{source}|#{query_text}") |> Base.encode16(case: :lower) |> String.slice(0, 32)
  end

  # Raw, per-execution samples tagged with the action (LiveView event / HTTP
  # route / Oban job) that was running when the query fired, for the "Query
  # Timeline" dashboard page. Kept in-memory only (not flushed to Postgres)
  # and trimmed to @timeline_retention on every flush tick.
  defp record_timeline_event(source, query, duration_ms) do
    {action, action_id} = Mehungry.Telemetry.ActionContext.current()
    query_text = (query || "unknown") |> to_string() |> String.slice(0, @query_text_limit)
    key = System.unique_integer([:positive, :monotonic])

    entry = %{
      time: DateTime.utc_now(),
      action: action,
      action_id: action_id,
      source: source,
      query: query_text,
      duration_ms: duration_ms
    }

    try do
      :ets.insert(@timeline_table, {key, entry})
    catch
      :error, :badarg -> :ok
    end
  end

  defp trim_timeline do
    cutoff = DateTime.add(DateTime.utc_now(), -@timeline_retention, :millisecond)

    :ets.tab2list(@timeline_table)
    |> Enum.each(fn {key, entry} ->
      if DateTime.compare(entry.time, cutoff) == :lt do
        :ets.delete(@timeline_table, key)
      end
    end)
  rescue
    e -> Logger.error("[MetricsBuffer] Timeline trim failed: #{inspect(e)}")
  end

  @doc "Raw query executions from the last `minutes`, newest first."
  def list_recent_query_events(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(), -minutes * 60, :second)

    :ets.tab2list(@timeline_table)
    |> Enum.map(fn {_key, entry} -> entry end)
    |> Enum.filter(fn entry -> DateTime.compare(entry.time, cutoff) != :lt end)
    |> Enum.sort_by(& &1.time, {:desc, DateTime})
  rescue
    _ -> []
  end

  defp flush_queries do
    entries = :ets.tab2list(@query_table)
    :ets.delete_all_objects(@query_table)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      entries
      |> Enum.group_by(fn {fingerprint, _} -> fingerprint end)
      |> Enum.map(fn {fingerprint, group} ->
        {_fp, {_value, query_text, source}} = List.first(group)
        values = group |> Enum.map(fn {_fp, {v, _q, _s}} -> v end) |> Enum.sort()
        count = length(values)
        p95_idx = max(0, ceil(0.95 * count) - 1)

        %{
          fingerprint: fingerprint,
          query: query_text,
          source: source,
          period_start: now,
          min: List.first(values),
          max: List.last(values),
          avg: Enum.sum(values) / count,
          p95: Enum.at(values, p95_idx),
          sample_count: count
        }
      end)

    if rows != [] do
      Mehungry.Repo.insert_all(Mehungry.Telemetry.QueryProfile, rows)
    end
  rescue
    e -> Logger.error("[MetricsBuffer] Query flush failed: #{inspect(e)}")
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval)
  end

  defp to_ms(native), do: System.convert_time_unit(native, :native, :millisecond) * 1.0

  defp oban_job_tags(metadata) do
    job = metadata[:job] || %{}
    %{queue: to_string(Map.get(job, :queue)), worker: to_string(Map.get(job, :worker))}
  end

  defp view_name(%{socket: %{view: view}}) when is_atom(view) do
    view |> Module.split() |> List.last()
  end

  defp view_name(_metadata), do: "unknown"
end
