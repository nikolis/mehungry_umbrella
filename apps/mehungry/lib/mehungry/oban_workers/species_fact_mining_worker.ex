defmodule Mehungry.ObanWorkers.SpeciesFactMiningWorker do
  @moduledoc """
  One job == **one `FoundementalFoodSpecies`** of an admin-triggered "Mine all
  species" sweep. It asks the external biomed-fact-miner for the species' facts and
  **replaces** that species' stored facts via `Mehungry.FactMining.mine_species/1`,
  then reports its outcome into the species' `SpeciesFactMiningRun` row.

  **Fan-out, not a single mega-job** — a server restart only interrupts the one
  species in flight (Oban rescues + retries it), while the rest are independent
  queued jobs that resume on boot. Runs on `:fact_mining` (concurrency 1 → sequential,
  which suits the slow, self-throttled miner). `max_attempts: 3`: a transient miner
  failure retries (mining is idempotent — wipe-then-insert), and on the **final**
  attempt the species is recorded as failed so the batch can still finalize.
  """

  use Oban.Worker, queue: :fact_mining, max_attempts: 3

  require Logger

  alias Mehungry.FactMining
  alias Mehungry.FactMining.SpeciesFactMiningRuns, as: Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    tracking_id = args["tracking_id"]
    species_id = args["species_id"]

    Runs.mark_processing(tracking_id)

    case FactMining.mine_species(species_id) do
      {:ok, counts} ->
        Logger.info(
          "[FactMining] species ##{species_id}: #{counts.total} facts " <>
            "(#{counts.verified} verified, #{counts.contradicted} contradicted)"
        )

        Runs.mark_completed(tracking_id, counts)
        :ok

      # Miner concurrency saturated (429). Back off per Retry-After without burning a
      # retry or marking the run failed. Revert the row to `pending` first: it yielded
      # its single slot and is no longer executing, so leaving it `processing` would
      # make the serialized batch falsely read as "every species processing at once".
      {:error, {:rate_limited, seconds}} ->
        Runs.mark_pending(tracking_id)
        {:snooze, seconds}

      {:error, reason} ->
        if job.attempt >= job.max_attempts do
          Logger.warning(
            "[FactMining] species ##{species_id} failed after #{job.attempt} attempts: " <>
              inspect(reason)
          )

          Runs.mark_failed(tracking_id, reason)
          :ok
        else
          # Will retry on a later slot — revert to `pending` so it isn't left
          # stuck `processing` while it waits (same leak as the 429 snooze).
          Runs.mark_pending(tracking_id)
          {:error, reason}
        end
    end
  end
end
