defmodule Mehungry.Literature.ResearchIngestionRuns do
  @moduledoc """
  Lifecycle + progress tracking for the admin-triggered research-ingestion run
  (the UI control for `mix research.ingest`, on `/professional/health`).

  The run **fans out** to one `Mehungry.ObanWorkers.ResearchIngestionWorker` job
  per condition (restart-safe: a reboot only interrupts the in-flight condition,
  which Oban rescues + retries, while the rest resume on boot). Each job reports
  its outcome here via atomic counter increments; the run finalizes when every
  condition has reported. Every change is broadcast on `Mehungry.PubSub` under
  `topic/0` so the Health Conditions admin view renders live progress. Only **one**
  run may be in flight — `enqueue/1` refuses a second (`{:error, :already_running}`).
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Health
  alias Mehungry.Literature.ResearchIngestionRun, as: Run
  alias Mehungry.ObanWorkers.ResearchIngestionWorker

  @topic "research_ingestion_runs"
  @worker "Mehungry.ObanWorkers.ResearchIngestionWorker"

  @doc "PubSub topic carrying `{:research_ingestion_run, %Run{}}` updates."
  def topic, do: @topic

  @doc "Most recent run, or nil."
  def latest_run do
    Repo.one(from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1))
  end

  @doc "The in-flight run (`status == \"processing\"`), or nil."
  def active_run do
    Repo.one(from(r in Run, where: r.status == "processing", order_by: [desc: r.id], limit: 1))
  end

  @doc """
  Start a run from the UI: resolve the conditions (optional case-insensitive name
  filter), open the tracking row, and **fan out one worker job per condition**
  (each carrying the run id + options). Refuses to start while another run is
  `processing`.

  `opts`: `:crawl`, `:force` (booleans), `:batch` (int), `:condition` (name filter).
  """
  def enqueue(opts \\ []) do
    case active_run() do
      %Run{} = run ->
        {:error, :already_running, run}

      nil ->
        conditions = resolve_conditions(opts[:condition])

        if conditions == [] do
          {:error, :no_conditions}
        else
          options = %{
            "crawl" => !!opts[:crawl],
            "force" => !!opts[:force],
            "batch" => opts[:batch] || 200,
            "condition" => opts[:condition]
          }

          run = start_run(length(conditions), options)

          Enum.each(conditions, fn condition ->
            %{
              "run_id" => run.id,
              "condition_id" => condition.id,
              "crawl" => options["crawl"],
              "force" => options["force"],
              "batch" => options["batch"]
            }
            |> ResearchIngestionWorker.new()
            |> Oban.insert()
          end)

          {:ok, run}
        end
    end
  end

  defp resolve_conditions(nil), do: Health.list_conditions()

  defp resolve_conditions(name) do
    term = name |> to_string() |> String.downcase()
    Enum.filter(Health.list_conditions(), &(String.downcase(&1.name) =~ term))
  end

  @doc "Open a `processing` run for `total` conditions. Broadcasts."
  def start_run(total, options \\ %{}) when is_integer(total) do
    {:ok, run} =
      %Run{}
      |> Run.changeset(%{
        status: "processing",
        options: options,
        conditions_total: total,
        started_at: now()
      })
      |> Repo.insert(returning: true)

    broadcast(run)
  end

  @doc "Mark the condition currently being analyzed (for the live label)."
  def start_condition(nil, _name), do: nil

  def start_condition(run_id, name) do
    from(r in Run, where: r.id == ^run_id and r.status == "processing")
    |> Repo.update_all(set: [current_condition: name])

    case Repo.get(Run, run_id) do
      nil -> nil
      run -> broadcast(run)
    end
  end

  @doc """
  Record one finished condition: advance progress + accumulate store counts
  (atomic `update_all` so concurrent/retried jobs don't clobber each other), then
  finalize the run if every condition has now reported.
  """
  def record_condition(nil, _counts), do: nil

  def record_condition(run_id, %{} = counts) do
    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(
      inc: [
        conditions_done: 1,
        inserted: Map.get(counts, :inserted, 0),
        updated: Map.get(counts, :updated, 0),
        unchanged: Map.get(counts, :unchanged, 0),
        skipped: Map.get(counts, :skipped, 0)
      ]
    )

    finalize(run_id)
  end

  @doc "Record a condition whose job exhausted its retries (keeps the run moving)."
  def record_condition_failure(nil, _reason), do: nil

  def record_condition_failure(run_id, reason) do
    error = reason |> inspect() |> String.slice(0, 500)

    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(inc: [conditions_failed: 1], set: [error: error])

    finalize(run_id)
  end

  # Finalize a processing run once every condition has reported: `failed` (red)
  # when *every* condition failed (e.g. the extractor was down the whole run),
  # otherwise `completed` (partial failures stay visible via `conditions_failed`).
  defp finalize(run_id) do
    case Repo.get(Run, run_id) do
      %Run{status: "processing"} = run ->
        run =
          if run.conditions_done + run.conditions_failed >= run.conditions_total,
            do: finalize_run(run),
            else: run

        broadcast(run)

      %Run{} = run ->
        broadcast(run)

      nil ->
        nil
    end
  end

  defp finalize_run(run) do
    attrs =
      if run.conditions_total > 0 and run.conditions_failed >= run.conditions_total do
        %{
          status: "failed",
          current_condition: nil,
          completed_at: now(),
          error: run.error || "every condition failed — check the extractor connection"
        }
      else
        %{status: "completed", current_condition: nil, completed_at: now()}
      end

    run |> Run.changeset(attrs) |> Repo.update!()
  end

  @doc """
  Cancel the in-flight run: cancel its remaining Oban jobs and mark it `failed`.
  The admin's escape hatch (e.g. the extractor is down and retries are churning).
  Already-stored work is kept. No-op when nothing is running.
  """
  def cancel_active do
    case active_run() do
      nil ->
        :noop

      %Run{} = run ->
        Oban.cancel_all_jobs(
          from(j in Oban.Job,
            where: j.worker == @worker and fragment("(args->>'run_id')::bigint = ?", ^run.id)
          )
        )

        fail(run.id, "cancelled by admin")
    end
  end

  @doc """
  Mark the active run `failed` if it has gone **stale** — it's `processing` but no
  longer has any live (schedulable/executing) Oban job backing it (e.g. its jobs
  were discarded after a crash). Lets the UI unwedge itself; returns the reconciled
  run or nil. Safe to call on mount.
  """
  def reconcile_stale do
    case active_run() do
      nil ->
        nil

      %Run{} = run ->
        if run_has_live_jobs?(run.id),
          do: nil,
          else: fail(run.id, "run stalled (no live jobs — likely a restart); re-run to resume")
    end
  end

  defp run_has_live_jobs?(run_id) do
    Repo.exists?(
      from(j in Oban.Job,
        where:
          j.worker == @worker and
            j.state in ["available", "scheduled", "executing", "retryable"] and
            fragment("(args->>'run_id')::bigint = ?", ^run_id)
      )
    )
  end

  defp fail(run_id, reason) do
    case Repo.get(Run, run_id) do
      nil ->
        nil

      run ->
        error = if is_binary(reason), do: reason, else: inspect(reason)

        run
        |> Run.changeset(%{
          status: "failed",
          current_condition: nil,
          error: String.slice(error, 0, 500),
          completed_at: now()
        })
        |> Repo.update!()
        |> broadcast()
    end
  end

  defp broadcast(%Run{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:research_ingestion_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
