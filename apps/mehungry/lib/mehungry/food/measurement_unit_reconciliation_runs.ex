defmodule Mehungry.Food.MeasurementUnitReconciliationRuns do
  @moduledoc """
  Lifecycle + progress tracking for the "reconcile numeric-named measurement
  units" admin action.

  Mirrors `Mehungry.Food.NutrientRecalculationRuns`: `start_run/1` opens a run
  with a fixed `total`, each `MeasurementUnitReconciliationWorker` job reports its
  outcome via `record_success/1` / `record_failure/2` (atomic `update_all`
  increments — jobs run concurrently on the `:imports` queue), and the run flips
  to `completed` once every job has reported. Every change is broadcast on
  `Mehungry.PubSub` under `topic/0` so the Measurement Units admin view can render
  live progress.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Food.MeasurementUnitReconciliationRun, as: Run

  @topic "measurement_unit_reconciliation_runs"

  @doc "PubSub topic carrying `{:measurement_unit_reconciliation_run, %Run{}}` updates."
  def topic, do: @topic

  @doc "Most recent run, or nil."
  def latest_run do
    Repo.one(from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1))
  end

  @doc "Opens a run for `total` units. A zero-unit run is completed immediately."
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

  def record_success(nil), do: nil

  def record_success(run_id) do
    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(inc: [completed: 1])

    finalize(run_id)
  end

  def record_failure(nil, _reason), do: nil

  def record_failure(run_id, reason) do
    error = reason |> inspect() |> String.slice(0, 500)

    from(r in Run, where: r.id == ^run_id)
    |> Repo.update_all(inc: [failed: 1], set: [error: error])

    finalize(run_id)
  end

  defp finalize(run_id) do
    case Repo.get(Run, run_id) do
      nil ->
        Logger.debug("MeasurementUnitReconciliationRuns: run #{run_id} missing, skipping finalize")
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
    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      @topic,
      {:measurement_unit_reconciliation_run, run}
    )

    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
