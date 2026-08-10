defmodule Mehungry.Food.NutrientRecalculationRuns do
  @moduledoc """
  Lifecycle + progress tracking for the "recompute all recipe nutrients" admin
  action.

  Mirrors `Mehungry.Food.CandidateDerivationRuns`, but the unit of progress is an
  Oban job: `start_run/1` opens a `NutrientRecalculationRun` with a fixed `total`,
  and each `RecipePutNutrientsWorker` job reports its outcome via
  `record_success/1` or `record_failure/2`. Those use an atomic `update_all`
  increment (jobs run concurrently on the `:default` queue), then flip the run to
  `completed` once `completed + failed >= total`. Every change is broadcast on
  `Mehungry.PubSub` under `topic/0` so `MehungryWeb.ProfessionalLive.Recipes` can
  render live progress.

  All the `record_*`/`mark_*` helpers accept a `nil` run id and no-op, so the
  same worker path serves single-recipe enqueues (which carry no `run_id`).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Food.NutrientRecalculationRun, as: Run

  @topic "nutrient_recalculation_runs"

  @doc "PubSub topic carrying `{:nutrient_recalculation_run, %Run{}}` updates."
  def topic, do: @topic

  @doc "Most recent run, or nil."
  def latest_run do
    Repo.one(from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1))
  end

  @doc """
  Opens a run for `total` recipes. A zero-recipe run is completed immediately so
  the UI never shows a run stuck at 0/0.
  """
  def start_run(total) when is_integer(total) and total >= 0 do
    now = now()
    done? = total == 0

    {:ok, run} =
      %Run{}
      |> Run.changeset(%{
        status: if(done?, do: "completed", else: "processing"),
        total: total,
        completed: 0,
        failed: 0,
        error: nil,
        started_at: now,
        completed_at: if(done?, do: now, else: nil)
      })
      |> Repo.insert(returning: true)

    broadcast(run)
    run
  end

  @doc "Atomically records one recipe successfully recomputed."
  def record_success(nil), do: nil

  def record_success(run_id) do
    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(inc: [completed: 1])

    finalize(run_id)
  end

  @doc "Atomically records one recipe that failed to recompute (stores a sample error)."
  def record_failure(nil, _reason), do: nil

  def record_failure(run_id, reason) do
    error = reason |> inspect() |> String.slice(0, 500)

    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(inc: [failed: 1], set: [error: error])

    finalize(run_id)
  end

  # Reload the (now-incremented) row and flip it to completed once every job has
  # reported. Concurrent finalizers may both observe "done" and both mark
  # completed — harmless, the transition is idempotent and only re-broadcasts.
  defp finalize(run_id) do
    case Repo.get(Run, run_id) do
      nil ->
        Logger.debug("NutrientRecalculationRuns: run #{run_id} missing, skipping finalize")
        nil

      %Run{status: "processing"} = run ->
        run =
          if run.completed + run.failed >= run.total do
            run
            |> Run.changeset(%{status: "completed", completed_at: now()})
            |> Repo.update!()
          else
            run
          end

        broadcast(run)
        run

      run ->
        broadcast(run)
        run
    end
  end

  defp broadcast(%Run{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:nutrient_recalculation_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
