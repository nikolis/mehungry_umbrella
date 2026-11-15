defmodule Mehungry.FactMining.ConditionFactMiningRuns do
  @moduledoc """
  Lifecycle + progress tracking for the admin-triggered "Mine all conditions" sweep
  (`/professional/health`) — the condition-scope twin of
  `Mehungry.FactMining.SpeciesFactMiningRuns`.

  The sweep **fans out** one `Mehungry.ObanWorkers.ConditionFactMiningWorker` job per
  `Mehungry.Health.Condition`, tracked by one `ConditionFactMiningRun` row per
  condition grouped by `batch_id` (so the LiveView can stream + patch each row O(1),
  and derive aggregate progress by counting over the batch). Each job advances its
  own row `pending → processing → completed | failed`. Every transition is broadcast
  on `Mehungry.PubSub` under `topic/0`: a slim `{:fact_mining_processing, batch_id,
  condition_id}` on the high-frequency processing edge, and a full
  `{:fact_mining_run, %Run{}}` (condition preloaded) on a terminal transition.
  Mirrors the per-unit tracking-row pattern of the S3 → USDA seed import
  (`oban_ui_connected_worker.md`).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Health
  alias Mehungry.FactMining
  alias Mehungry.FactMining.ConditionFactMiningRun, as: Run
  alias Mehungry.ObanWorkers.ConditionFactMiningWorker

  @topic "condition_fact_mining_runs"
  @worker "Mehungry.ObanWorkers.ConditionFactMiningWorker"

  @doc "PubSub topic carrying `{:fact_mining_run, %Run{}}` + `{:fact_mining_processing, …}`."
  def topic, do: @topic

  @doc """
  Start a "Mine all conditions" batch: pre-flight the miner, open one `pending`
  tracking row per condition, and **fan out** one worker job per condition via a
  single `Oban.insert_all` (not a per-row loop — the NOTIFY-storm hazard). Returns
  `{:ok, batch_id}`, `{:error, {:unreachable, reason}}` when the miner is down, or
  `{:error, :no_conditions}`.
  """
  def mine_all_conditions do
    with :ok <- check_reachable() do
      case Health.list_conditions() do
        [] -> {:error, :no_conditions}
        conditions -> {:ok, enqueue_batch(conditions, nil)}
      end
    end
  end

  @doc """
  Mine a **single** condition — the per-condition twin of `mine_all_conditions/0`,
  for the per-card "Mine facts" button. Pre-flights the miner, opens one `pending`
  tracking row in its own `batch_id`, and enqueues one worker job on the same
  serialized `:fact_mining` queue. `query` is the admin's (optionally edited) prompt
  — stored on the row and carried in the job args; `nil`/blank falls back to the
  default `FactMining.query_for_condition/1` at mine time. Returns `{:ok, batch_id}`,
  `{:error, {:unreachable, reason}}`, or `{:error, :not_found}`.
  """
  def mine_condition(condition_id, query \\ nil) do
    # Pre-flight the miner, resolve the condition, then refuse a second mine while
    # one is already in flight (the user-facing notification). `enqueue_one/2`
    # re-checks atomically via Oban `unique` to close the click-race window.
    with :ok <- check_reachable(),
         {:ok, condition} <- fetch_condition(condition_id),
         :clear <- mine_guard(condition) do
      enqueue_one(condition, query)
    end
  end

  defp fetch_condition(condition_id) do
    case Health.get_condition(condition_id) do
      nil -> {:error, :not_found}
      condition -> {:ok, condition}
    end
  end

  defp mine_guard(condition) do
    if active_mine_for_condition(condition.id),
      do: {:error, {:already_running, condition.id}},
      else: :clear
  end

  @doc """
  The live `Oban.Job` for a condition's mine — one that is `available`, `scheduled`,
  `executing`, or `retryable` — or `nil` when none is in flight. Used both to block
  a duplicate trigger and to drive the "already mining" UI state. A `completed`/
  `cancelled` job does not count, so re-mining a finished condition is allowed.
  """
  def active_mine_for_condition(condition_id) do
    Repo.one(
      from(j in Oban.Job,
        where:
          j.worker == @worker and
            j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("(?->>'condition_id')::bigint = ?", j.args, ^condition_id),
        limit: 1
      )
    )
  end

  defp check_reachable do
    case FactMining.reachable?() do
      :ok -> :ok
      {:error, reason} -> {:error, {:unreachable, reason}}
    end
  end

  # Single-condition enqueue with the Oban `unique` backstop. Opens the `pending`
  # tracking row, then inserts the job via `Oban.insert/1` (NOT `insert_all`, which
  # bypasses uniqueness). If the worker's `unique` constraint catches a concurrent
  # duplicate (`conflict?: true`), the just-created row is an orphan with no job of
  # its own — delete it and report `:already_running` so the UI never shows a stuck
  # "pending" row. Returns `{:ok, batch_id}` or `{:error, {:already_running, id}}`.
  defp enqueue_one(condition, query) do
    batch_id = Ecto.UUID.generate()

    {:ok, run} =
      %Run{}
      |> Run.changeset(%{
        batch_id: batch_id,
        condition_id: condition.id,
        status: "pending",
        query: query
      })
      |> Repo.insert()

    job =
      ConditionFactMiningWorker.new(%{
        "tracking_id" => run.id,
        "condition_id" => condition.id,
        "batch_id" => batch_id,
        "query" => query
      })

    case Oban.insert(job) do
      {:ok, %Oban.Job{conflict?: true}} ->
        Repo.delete(run)
        {:error, {:already_running, condition.id}}

      {:ok, %Oban.Job{}} ->
        {:ok, batch_id}
    end
  end

  # Open one `pending` tracking row per condition under a fresh `batch_id` and fan
  # out one worker job each via a single `Oban.insert_all` (never a per-row loop —
  # the NOTIFY-storm hazard). Used by the dormant "all" sweep (`query` nil → default);
  # single-condition mines go through `enqueue_one/2` for the uniqueness backstop.
  defp enqueue_batch(conditions, query) do
    batch_id = Ecto.UUID.generate()
    now = now()

    rows =
      Enum.map(conditions, fn c ->
        %{
          batch_id: batch_id,
          condition_id: c.id,
          status: "pending",
          facts_total: 0,
          verified_count: 0,
          contradicted_count: 0,
          query: query,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_, inserted} = Repo.insert_all(Run, rows, returning: [:id, :condition_id])

    inserted
    |> Enum.map(fn r ->
      ConditionFactMiningWorker.new(%{
        "tracking_id" => r.id,
        "condition_id" => r.condition_id,
        "batch_id" => batch_id,
        "query" => query
      })
    end)
    |> Oban.insert_all()

    batch_id
  end

  @doc "Mark a condition row `processing` + broadcast the slim progress signal."
  def mark_processing(nil), do: nil

  def mark_processing(tracking_id) do
    from(r in Run, where: r.id == ^tracking_id and r.status == "pending")
    |> Repo.update_all(set: [status: "processing", started_at: now(), updated_at: now()])

    case Repo.get(Run, tracking_id) do
      nil ->
        nil

      %Run{} = run ->
        Phoenix.PubSub.broadcast(
          Mehungry.PubSub,
          @topic,
          {:fact_mining_processing, run.batch_id, run.condition_id}
        )

        run
    end
  end

  @doc """
  Revert a row back to `pending` — the job yielded its `:fact_mining` slot without
  finishing (a 429 `:snooze`, or a non-final error that will retry), so it is **not**
  currently executing.

  Without this the row would stay `processing` forever: the worker only ever moves a
  row *forward* to `processing` (and then to a terminal state on success/last
  failure), so a job that snoozes or retries leaks its `processing` status. Over a
  serialized, one-at-a-time batch that leak makes every condition look like it is
  processing at once even though `limit: 1` only ever runs one. Broadcasts the full
  row so the UI badge reverts to pending.
  """
  def mark_pending(nil), do: nil

  def mark_pending(tracking_id) do
    case Repo.get(Run, tracking_id) do
      nil ->
        nil

      %Run{} = run ->
        run
        |> Run.changeset(%{status: "pending", started_at: nil})
        |> Repo.update!()
        |> Repo.preload(:condition)
        |> broadcast_run()
    end
  end

  @doc "Record a condition row as `completed` with its fact counts. Broadcasts the full row."
  def mark_completed(nil, _counts), do: nil

  def mark_completed(tracking_id, %{} = counts) do
    update_terminal(tracking_id, %{
      status: "completed",
      facts_total: Map.get(counts, :total, 0),
      verified_count: Map.get(counts, :verified, 0),
      contradicted_count: Map.get(counts, :contradicted, 0),
      error: nil,
      completed_at: now()
    })
  end

  @doc "Record a condition row as `failed` (retries exhausted). Broadcasts the full row."
  def mark_failed(nil, _reason), do: nil

  def mark_failed(tracking_id, reason) do
    update_terminal(tracking_id, %{
      status: "failed",
      error: reason |> inspect() |> String.slice(0, 500),
      completed_at: now()
    })
  end

  defp update_terminal(tracking_id, attrs) do
    case Repo.get(Run, tracking_id) do
      nil ->
        Logger.debug("ConditionFactMiningRuns: row #{tracking_id} missing, skipping finalize")
        nil

      %Run{} = run ->
        run
        |> Run.changeset(attrs)
        |> Repo.update!()
        |> Repo.preload(:condition)
        |> broadcast_run()
    end
  end

  defp broadcast_run(%Run{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:fact_mining_run, run})
    run
  end

  # ── Reads ────────────────────────────────────────────────────────────────────

  @doc "The `batch_id` of the most recently started batch, or nil."
  def latest_batch_id do
    Repo.one(
      from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1, select: r.batch_id)
    )
  end

  @doc "All tracking rows for a batch (condition preloaded), condition-name ordered."
  def list_batch_rows(nil), do: []

  def list_batch_rows(batch_id) do
    Repo.all(
      from(r in Run,
        join: c in assoc(r, :condition),
        where: r.batch_id == ^batch_id,
        order_by: [asc: c.name],
        preload: [condition: c]
      )
    )
  end

  @doc """
  Aggregate progress for a batch: a `%{pending, processing, completed, failed,
  cancelled, total, facts_total, started_at}` summary derived by counting over `batch_id`.
  `started_at` is the earliest moment any condition in the batch began processing
  (nil until the first one starts) — the anchor the LiveView derives an ETA from.
  """
  def counts_for_batch(nil), do: empty_counts()

  def counts_for_batch(batch_id) do
    by_status =
      Repo.all(
        from(r in Run,
          where: r.batch_id == ^batch_id,
          group_by: r.status,
          select: {r.status, count(r.id)}
        )
      )
      |> Map.new()

    facts_total =
      Repo.one(
        from(r in Run, where: r.batch_id == ^batch_id, select: coalesce(sum(r.facts_total), 0))
      )

    started_at =
      Repo.one(
        from(r in Run,
          where: r.batch_id == ^batch_id and not is_nil(r.started_at),
          select: min(r.started_at)
        )
      )

    %{
      pending: Map.get(by_status, "pending", 0),
      processing: Map.get(by_status, "processing", 0),
      completed: Map.get(by_status, "completed", 0),
      failed: Map.get(by_status, "failed", 0),
      cancelled: Map.get(by_status, "cancelled", 0),
      total: by_status |> Map.values() |> Enum.sum(),
      facts_total: facts_total,
      started_at: started_at
    }
  end

  @doc "True while a batch still has `pending`/`processing` rows."
  def batch_in_flight?(nil), do: false

  def batch_in_flight?(batch_id) do
    Repo.exists?(
      from(r in Run, where: r.batch_id == ^batch_id and r.status in ["pending", "processing"])
    )
  end

  @doc """
  Cancel a batch: cancel its remaining Oban jobs, then mark any still-unfinished
  rows `cancelled`. Already-mined facts are kept.
  """
  def cancel_batch(nil), do: :noop

  def cancel_batch(batch_id) do
    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker == @worker and fragment("args->>'batch_id' = ?", ^batch_id)
      )
    )

    from(r in Run, where: r.batch_id == ^batch_id and r.status in ["pending", "processing"])
    |> Repo.update_all(
      set: [status: "cancelled", error: nil, completed_at: now(), updated_at: now()]
    )

    :cancelled
  end

  defp empty_counts,
    do: %{
      pending: 0,
      processing: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
      total: 0,
      facts_total: 0,
      started_at: nil
    }

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
