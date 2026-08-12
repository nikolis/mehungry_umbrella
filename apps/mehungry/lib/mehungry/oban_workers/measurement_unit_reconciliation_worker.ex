defmodule Mehungry.ObanWorkers.MeasurementUnitReconciliationWorker do
  @moduledoc """
  Reconciles one measurement unit whose name is a bare USDA NDB number.

  Looks the number up in the USDA FDC API (`FdcClient.lookup_name_by_ndb_number/1`)
  and, on a hit, replaces the numeric name with the real food description while
  preserving the code in `ndb_number`. Runs on the `:imports` queue so the USDA
  API is hit politely (2 concurrent), and returns `{:snooze, secs}` on a
  rate-limit so a throttled lookup is retried later without counting as a
  failure. Outcome is reported into the batch's `MeasurementUnitReconciliationRun`
  via the `run_id` arg (absent for ad-hoc single enqueues — then the record_*
  calls no-op).
  """

  use Oban.Worker,
    queue: :imports,
    max_attempts: 5

  require Logger

  alias Mehungry.Food.Measurements
  alias Mehungry.Food.MeasurementUnitReconciliationRuns, as: Runs
  alias Mehungry.FoodData.Usda.FdcClient

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    unit_id = args["measurement_unit_id"]
    run_id = args["run_id"]

    unit = Measurements.get_measurement_unit!(unit_id)

    cond do
      is_nil(unit) ->
        Runs.record_failure(run_id, :unit_not_found)
        :ok

      # Already reconciled since enqueue (name no longer a bare number) — count
      # it as done rather than re-querying USDA.
      not Measurements.numeric_measurement_unit_name?(unit.name) ->
        Runs.record_success(run_id)
        :ok

      true ->
        reconcile(unit, run_id, job)
    end
  end

  defp reconcile(unit, run_id, job) do
    case FdcClient.lookup_name_by_ndb_number(unit.name) do
      {:ok, %{name: real_name}, _meta} ->
        case Measurements.reconcile_measurement_unit(unit, real_name) do
          {:ok, updated} ->
            Logger.info(
              "[MeasurementUnitReconciliation] ##{unit.id} \"#{unit.name}\" → \"#{updated.name}\""
            )

            Runs.record_success(run_id)
            :ok

          {:error, reason} ->
            Runs.record_failure(run_id, reason)
            :ok
        end

      # Politely back off and retry later; not counted as a failure.
      {:error, {:rate_limited, retry_after}} ->
        {:snooze, max(retry_after, 1)}

      {:error, :no_ndb_match} ->
        Runs.record_failure(run_id, "no USDA SR Legacy food for NDB #{unit.name}")
        :ok

      {:error, reason} ->
        # Transient (network/unexpected) — let Oban retry; count only on the last
        # attempt so the run can still complete.
        if job.attempt >= job.max_attempts do
          Runs.record_failure(run_id, reason)
          :ok
        else
          {:error, reason}
        end
    end
  end
end
