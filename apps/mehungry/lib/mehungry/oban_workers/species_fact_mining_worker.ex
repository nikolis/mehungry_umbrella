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

  **One in-flight mine per species** — `unique` keyed on `species_id` across the
  non-terminal states refuses a second job for a species that already has one
  queued/executing/retrying (so a double-click or re-trigger can't spawn an
  overlapping ~15-min miner call that wipe-replaces the same rows). `completed`/
  `discarded`/`cancelled` are excluded, so re-mining a *finished* species is still
  allowed. Enforced only through `Oban.insert/1` (the single-species enqueue path in
  `SpeciesFactMiningRuns.mine_species/2`), not the dormant bulk `insert_all` sweep.
  """

  use Oban.Worker,
    queue: :fact_mining,
    max_attempts: 3,
    unique: [
      keys: [:species_id],
      states: [:available, :scheduled, :executing, :retryable],
      period: :infinity
    ]

  require Logger

  alias Mehungry.FactMining
  alias Mehungry.FactMining.SpeciesFactMiningRuns, as: Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    tracking_id = args["tracking_id"]
    species_id = args["species_id"]

    Runs.mark_processing(tracking_id)

    # `args["query"]` is the admin's custom prompt (nil for dormant bulk jobs →
    # `mine_species/2` falls back to the default `query_for_species/1`).
    case FactMining.mine_species(species_id, query: args["query"]) do
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
