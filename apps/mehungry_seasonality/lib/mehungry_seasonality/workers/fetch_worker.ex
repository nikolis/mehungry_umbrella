defmodule MehungrySeasonality.Workers.FetchWorker do
  @moduledoc """
  One job == **one species in one country** of an admin-triggered "Fetch <country>"
  sweep. It runs `MehungrySeasonality.Fetcher.fetch_species/2` (idempotent — each
  fetch replaces that species × country's observations) and reports its outcome into
  the species' `Run` row.

  Runs on the dedicated single-slot `:seasonality` queue, so the two public APIs are
  called sequentially. `max_attempts: 3`: a transient API failure retries, and on the
  **final** attempt the species is recorded as failed so the batch can still finish.
  """

  use Oban.Worker, queue: :seasonality, max_attempts: 3

  require Logger

  alias MehungrySeasonality.{Fetcher, Runs}

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
    tracking_id = args["tracking_id"]
    species_id = args["species_id"]
    country = args["country"]

    Runs.mark_processing(tracking_id)

    try do
      counts = Fetcher.fetch_species(species_id, country)

      Logger.info(
        "[Seasonality] species ##{species_id} #{country}: " <>
          "#{counts.local} local + #{counts.import} import months"
      )

      Runs.mark_completed(tracking_id, counts)
      :ok
    rescue
      error ->
        if job.attempt >= job.max_attempts do
          Logger.warning(
            "[Seasonality] species ##{species_id} #{country} failed after " <>
              "#{job.attempt} attempts: " <> Exception.message(error)
          )

          Runs.mark_failed(tracking_id, Exception.message(error))
          :ok
        else
          reraise error, __STACKTRACE__
        end
    end
  end
end
