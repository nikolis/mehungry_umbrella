defmodule Mehungry.Telemetry.MetricsBuffer do
  @moduledoc """
  Central telemetry collector. Attaches `:telemetry` handlers for repo
  queries, HTTP/LiveView dispatch, Oban jobs, cache sizes, and VM stats, and
  buffers every sample in three ETS tables owned by this GenServer:

    * `#{inspect(__MODULE__)}` — generic `{metric, tags} => value` samples
      (one entry per event), aggregated on flush into
      `Mehungry.Telemetry.Snapshot` rows.
    * `QueryTimes` — repo query samples keyed by
      `fingerprint_query/2` (source + SQL shape), aggregated on flush into
      `Mehungry.Telemetry.QueryProfile` rows.
    * `QueryTimeline` — raw, unaggregated repo query executions tagged with
      the action (`Mehungry.Telemetry.ActionContext`) that triggered them,
      for the LiveDashboard "Query Timeline" page. Kept in-memory only —
      never flushed to Postgres — and trimmed to the last 60 minutes on
      every flush tick.

  A timer fires every 5 minutes (`schedule_flush/0`) to aggregate and
  persist the two Postgres-backed tables and prune the timeline table. See
  `docs/observability.md` for the full architecture, metric reference, and
  diagnostic playbooks.
  """

  use GenServer
  require Logger
  import Ecto.Query

  @table __MODULE__
  @query_table Module.concat(__MODULE__, QueryTimes)
  @timeline_table Module.concat(__MODULE__, QueryTimeline)
  @flush_interval :timer.minutes(5)
  @query_text_limit 1_000
  @timeline_retention :timer.minutes(60)
  # Monotonic timestamp (ms) of the last generic-table flush/clear, so readers
  # can turn the live count-since-flush into a per-minute rate. See
  # `since_last_flush_ms/0`.
  @flush_key {__MODULE__, :last_flush}

  @doc "Starts the GenServer under the given `opts`, registered as `#{inspect(__MODULE__)}`."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(_opts) do
    :ets.new(@table, [:public, :named_table, :duplicate_bag])
    :ets.new(@query_table, [:public, :named_table, :duplicate_bag])
    :ets.new(@timeline_table, [:public, :named_table, :ordered_set])
    mark_flushed()
    attach_handlers()
    schedule_flush()
    {:ok, %{}}
  end

  @doc "Every `@flush_interval` (5 min): aggregates and persists both ETS tables, then prunes the timeline."
  @impl true
  def handle_info(:flush, state) do
    flush()
    mark_flushed()
    flush_queries()
    trim_timeline()
    schedule_flush()
    {:noreply, state}
  end

  @doc """
  Milliseconds since the generic metrics table was last flushed (and cleared),
  or `nil` if the buffer has not booted yet. The live count returned by
  `live_route_counts/2` accumulated over this window, so `count / (ms / 60_000)`
  is the current per-minute rate.
  """
  def since_last_flush_ms do
    case :persistent_term.get(@flush_key, nil) do
      ts when is_integer(ts) -> System.monotonic_time(:millisecond) - ts
      _ -> nil
    end
  end

  @doc """
  Live per-route request counts accumulated in the in-memory buffer since the
  last flush, for the given `metric` whose `route` tag starts with
  `route_prefix`. Reads the public ETS table directly (values keyed by an atom
  `:route` in-memory, unlike the string-keyed `tags` in flushed snapshots) and
  returns `%{route => count}`, or `%{}` if the table does not exist yet.
  """
  def live_route_counts(metric, route_prefix) do
    @table
    |> safe_tab2list()
    |> Enum.reduce(%{}, fn
      {{^metric, tags}, _value}, acc ->
        route = tags[:route] || tags["route"]

        if is_binary(route) and String.starts_with?(route, route_prefix) do
          Map.update(acc, route, 1, &(&1 + 1))
        else
          acc
        end

      _other, acc ->
        acc
    end)
  end

  defp mark_flushed do
    :persistent_term.put(@flush_key, System.monotonic_time(:millisecond))
  end

  defp safe_tab2list(table) do
    :ets.tab2list(table)
  rescue
    ArgumentError -> []
  catch
    :error, :badarg -> []
  end

  # --- Telemetry handlers ---
  #
  # Each of these is attached (see `attach_handlers/0`) to one `:telemetry`
  # event and records one or more samples into the ETS tables via `record/3`
  # (generic metrics), `record_query/3` and `record_timeline_event/3` (repo
  # queries). They run synchronously in the emitting process, so they must
  # stay cheap and never raise.

  @doc """
  Handles `[:mehungry, :repo, :query]`. Records the query's own `query_time`
  (grouped by `fingerprint_query/2` into the per-statement `QueryTimes`
  table, and appended to the raw `QueryTimeline` table), plus
  `"mehungry.repo.query.total_time"` and `"mehungry.repo.query.queue_time"`
  tagged by `source`.
  """
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

  @doc """
  Handles `[:phoenix, :router_dispatch, :stop]`. Records
  `"phoenix.request.duration"` tagged by `route`.
  """
  def handle_router_dispatch(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      record("phoenix.request.duration", %{route: metadata[:route] || "unknown"}, to_ms(duration))
    end
  end

  @doc """
  Handles `[:phoenix, :live_view, :mount, :stop]`. Records
  `"live_view.mount.duration"` tagged by the mounted view's module name.
  """
  def handle_live_view_mount(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      record("live_view.mount.duration", %{view: view_name(metadata)}, to_ms(duration))
    end
  end

  @doc """
  Handles `[:phoenix, :live_view, :handle_event, :stop]`. Records
  `"live_view.handle_event.duration"` tagged by view and `event` name.
  """
  def handle_live_view_event(_event, measurements, metadata, _config) do
    with duration when is_integer(duration) <- measurements[:duration] do
      tags = %{view: view_name(metadata), event: to_string(metadata[:event] || "unknown")}
      record("live_view.handle_event.duration", tags, to_ms(duration))
    end
  end

  @doc """
  Handles `[:oban, :job, :stop]`. Records `"oban.job.duration"` and
  `"oban.job.queue_time"`, both tagged by `queue` and `worker`
  (`oban_job_tags/1`).
  """
  def handle_oban_job_stop(_event, measurements, metadata, _config) do
    tags = oban_job_tags(metadata)

    with duration when is_integer(duration) <- measurements[:duration] do
      record("oban.job.duration", tags, to_ms(duration))
    end

    with queue_time when is_integer(queue_time) <- measurements[:queue_time] do
      record("oban.job.queue_time", tags, to_ms(queue_time))
    end
  end

  @doc """
  Handles `[:oban, :job, :exception]`. Records one `"oban.job.exception.count"`
  sample (value `1.0`) tagged by `queue` and `worker`.
  """
  def handle_oban_job_exception(_event, _measurements, metadata, _config) do
    record("oban.job.exception.count", oban_job_tags(metadata), 1.0)
  end

  @doc """
  Handles `[:mehungry, :cache]`, emitted by the Cachex-wrapping code for each
  named cache. Records `"mehungry.cache.size"` tagged by `cache`.
  """
  def handle_cache_size(_event, measurements, metadata, _config) do
    with size when is_integer(size) <- measurements[:size] do
      record("mehungry.cache.size", %{cache: to_string(metadata[:cache])}, size * 1.0)
    end
  end

  @doc """
  Handles `[:mehungry, :oban, :queue]`, emitted by the periodic queue-depth
  poller. Records `"mehungry.oban.queue.depth"` tagged by `queue`.
  """
  def handle_oban_queue_depth(_event, measurements, metadata, _config) do
    with depth when is_integer(depth) <- measurements[:depth] do
      record("mehungry.oban.queue.depth", %{queue: to_string(metadata[:queue])}, depth * 1.0)
    end
  end

  @doc """
  Handles `[:mehungry, :vm, :process]`, emitted by the process watchdog poll.
  Records `"mehungry.vm.process.max_message_queue"` (the largest mailbox
  seen) and `"mehungry.vm.process.over_threshold_count"` (how many processes
  were over the `[ProcessWatchdog]` mailbox threshold), both untagged.
  """
  def handle_vm_process_stats(_event, measurements, _metadata, _config) do
    record(
      "mehungry.vm.process.max_message_queue",
      %{},
      (measurements[:max_message_queue] || 0) * 1.0
    )

    record(
      "mehungry.vm.process.over_threshold_count",
      %{},
      (measurements[:over_threshold_count] || 0) * 1.0
    )
  end

  @doc """
  Handles `[:mehungry, :vm, :scheduler]`, emitted by the periodic scheduler
  poll. Records `"mehungry.vm.scheduler.utilization"` and
  `"mehungry.vm.scheduler.weighted"`, both untagged.
  """
  def handle_vm_scheduler(_event, measurements, _metadata, _config) do
    with utilization when is_number(utilization) <- measurements[:utilization] do
      record("mehungry.vm.scheduler.utilization", %{}, utilization * 1.0)
    end

    with weighted when is_number(weighted) <- measurements[:weighted] do
      record("mehungry.vm.scheduler.weighted", %{}, weighted * 1.0)
    end
  end

  @doc """
  Handles `[:vm, :memory]` (emitted by `:telemetry_poller`'s built-in VM
  memory measurement). Records `"vm.memory.total"` in kilobytes, untagged.
  """
  def handle_vm_memory(_event, measurements, _metadata, _config) do
    with total when is_integer(total) <- measurements[:total] do
      record("vm.memory.total", %{}, total / 1024.0)
    end
  end

  @doc """
  Handles `[:mehungry, :vm, :live_view]`, emitted by the periodic LiveView
  process count poll. Records `"mehungry.vm.live_view.count"`, untagged.
  """
  def handle_vm_live_view_count(_event, measurements, _metadata, _config) do
    with count when is_integer(count) <- measurements[:count] do
      record("mehungry.vm.live_view.count", %{}, count * 1.0)
    end
  end

  @doc """
  Handles `[:mehungry, :repo, :pool]`, emitted by the periodic DBConnection
  pool poll. Records `"mehungry.repo.pool.busy"`, `"mehungry.repo.pool.total"`,
  and `"mehungry.repo.pool.pool_size"`, all untagged.
  """
  def handle_repo_pool_stats(_event, measurements, _metadata, _config) do
    record("mehungry.repo.pool.busy", %{}, (measurements[:busy] || 0) * 1.0)
    record("mehungry.repo.pool.total", %{}, (measurements[:total] || 0) * 1.0)
    record("mehungry.repo.pool.pool_size", %{}, (measurements[:pool_size] || 0) * 1.0)
  end

  # --- Private ---

  # Wires each `handle_*` function above to its `:telemetry` event. Attach
  # ids are unique per-clause so re-attaching (e.g. hot code reload) is a
  # no-op rather than a crash.
  defp attach_handlers do
    handlers = [
      {"buffer-repo-query", [:mehungry, :repo, :query], &handle_repo_query/4},
      {"buffer-router-dispatch", [:phoenix, :router_dispatch, :stop], &handle_router_dispatch/4},
      {"buffer-lv-mount", [:phoenix, :live_view, :mount, :stop], &handle_live_view_mount/4},
      {"buffer-lv-event", [:phoenix, :live_view, :handle_event, :stop],
       &handle_live_view_event/4},
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

  @doc """
  Deterministic id for a query "shape": `source` (the Ecto schema/table name)
  plus the raw SQL text, hashed with SHA-256. Used to group per-execution
  samples into one `query_time_profiles` row instead of one row per literal
  execution — the same `{source, query_text}` pair always hashes to the same
  fingerprint, across processes and restarts, so a query's historical rows
  stay comparable on the LiveDashboard "Queries" page.

  ## Examples

      iex> Mehungry.Telemetry.MetricsBuffer.fingerprint_query("recipes", "SELECT * FROM recipes WHERE id = $1")
      "c9d1f7de985b002152f408a6496e45f1"

      iex> Mehungry.Telemetry.MetricsBuffer.fingerprint_query("recipes", "SELECT * FROM recipes WHERE id = $1") ==
      ...>   Mehungry.Telemetry.MetricsBuffer.fingerprint_query("recipes", "SELECT * FROM recipes WHERE id = $1")
      true

  """
  def fingerprint_query(source, query_text) do
    :crypto.hash(:sha256, "#{source}|#{query_text}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 32)
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

  @doc """
  Raw query executions from the last `minutes`, newest first — backs the
  LiveDashboard "Query Timeline" page. Reads the in-memory `QueryTimeline`
  ETS table directly (never touches Postgres), so it only sees events from
  roughly the last #{div(:timer.minutes(60), 60_000)} minutes regardless of
  `minutes` (see the module doc on `@timeline_retention`), and returns `[]`
  rather than raising if the table doesn't exist yet (e.g. right after boot).
  Not doctested: results depend on real, in-flight query traffic.
  """
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
