defmodule Mehungry.ObanWorkers.SpeciesEnrichmentWorker do
  @moduledoc """
  One job == **one `FoundementalFoodSpecies`** of an admin-triggered "Enrich all
  species" sweep. It fetches the species' Wikidata (CC0) + FAOSTAT (CC-BY) facts via
  `Mehungry.Food.enrich_species/2` (idempotent upserts into `species_facts` — FAOSTAT
  auto-promoted, Wikidata left pending for review) and reports its outcome into the
  species' `SpeciesEnrichmentRun` row.

  **Fan-out, not a single mega-job** — a server restart only interrupts the one species
  in flight (Oban rescues + retries it), while the rest are independent queued jobs that
  resume on boot. Runs on `:species_enrichment` (concurrency 1 → sequential, polite to
  the Wikidata API). `max_attempts: 3`: a transient fetch failure retries (upserts are
  idempotent), and on the **final** attempt the species is recorded as failed so the
  batch can still finalize.
  """

  use Oban.Worker, queue: :species_enrichment, max_attempts: 3

  require Logger

  alias Mehungry.Food
  alias Mehungry.Food.SpeciesEnrichmentRuns, as: Runs

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    tracking_id = args["tracking_id"]
    species_id = args["species_id"]

    Runs.mark_processing(tracking_id)

    try do
      species = Food.get_foundemental_species!(species_id)
      counts = Food.enrich_species(species)

      Logger.info(
        "[SpeciesEnrichment] species ##{species_id}: " <>
          "#{counts.wikidata} Wikidata + #{counts.faostat} FAOSTAT facts"
      )

      Runs.mark_completed(tracking_id, counts)
      :ok
    rescue
      error ->
        if job.attempt >= job.max_attempts do
          Logger.warning(
            "[SpeciesEnrichment] species ##{species_id} failed after #{job.attempt} attempts: " <>
              Exception.message(error)
          )

          Runs.mark_failed(tracking_id, Exception.message(error))
          :ok
        else
          reraise error, __STACKTRACE__
        end
    end
  end
end
