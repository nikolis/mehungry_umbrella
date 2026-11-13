defmodule Mehungry.Food.SpeciesEnrichmentRuns do
  @moduledoc """
  Lifecycle + progress tracking for the admin-triggered "Enrich all species" sweep
  (`/professional/species-enrichment`) — the production trigger for what
  `mix species.enrich` does locally.

  The sweep **fans out** one `Mehungry.ObanWorkers.SpeciesEnrichmentWorker` job per
  `FoundementalFoodSpecies`, tracked by one `SpeciesEnrichmentRun` row per species
  grouped by `batch_id` (so the LiveView can stream + patch each row O(1), and derive
  aggregate progress by counting over the batch). Each job advances its own row
  `pending → processing → completed | failed`. Every transition is broadcast on
  `Mehungry.PubSub` under `topic/0`: a slim `{:enrichment_processing, batch_id,
  species_id}` on the high-frequency processing edge, and a full `{:enrichment_run,
  %Run{}}` (species preloaded) on a terminal transition. Mirrors the per-unit
  tracking-row pattern of `Mehungry.FactMining.SpeciesFactMiningRuns`
  (`oban_ui_connected_worker.md`).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.SpeciesEnrichmentRun, as: Run
  alias Mehungry.ObanWorkers.SpeciesEnrichmentWorker

  @topic "species_enrichment_runs"
  @worker "Mehungry.ObanWorkers.SpeciesEnrichmentWorker"

  @doc "PubSub topic carrying `{:enrichment_run, %Run{}}` + `{:enrichment_processing, …}`."
  def topic, do: @topic

  @doc """
  Start an "Enrich all species" batch: open one `pending` tracking row per species and
  **fan out** one worker job per species via a single `Oban.insert_all` (not a per-row
  loop — the NOTIFY-storm hazard). Returns `{:ok, batch_id}` or `{:error, :no_species}`.

  No reachability pre-flight: Wikidata/FAOSTAT fetch failures degrade to `0` facts (the
  job still completes), unlike the fact-miner which can be wholly down.
  """
  def enrich_all_species do
    case Food.list_foundemental_species() do
      [] ->
        {:error, :no_species}

      species ->
        batch_id = Ecto.UUID.generate()
        # `timestamps()` columns are :naive_datetime; insert_all needs them explicit.
        now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

        rows =
          Enum.map(species, fn s ->
            %{
              batch_id: batch_id,
              foundemental_species_id: s.id,
              status: "pending",
              wikidata_count: 0,
              faostat_count: 0,
              inserted_at: now,
              updated_at: now
            }
          end)

        {_, inserted} =
          Repo.insert_all(Run, rows, returning: [:id, :foundemental_species_id])

        inserted
        |> Enum.map(fn r ->
          SpeciesEnrichmentWorker.new(%{
            "tracking_id" => r.id,
            "species_id" => r.foundemental_species_id,
            "batch_id" => batch_id
          })
        end)
        |> Oban.insert_all()

        {:ok, batch_id}
    end
  end

  @doc "Mark a species row `processing` + broadcast the slim progress signal."
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
          {:enrichment_processing, run.batch_id, run.foundemental_species_id}
        )

        run
    end
  end

  @doc "Record a species row as `completed` with its per-source counts. Broadcasts the full row."
  def mark_completed(nil, _counts), do: nil

  def mark_completed(tracking_id, %{} = counts) do
    update_terminal(tracking_id, %{
      status: "completed",
      wikidata_count: Map.get(counts, :wikidata, 0),
      faostat_count: Map.get(counts, :faostat, 0),
      error: nil,
      completed_at: now()
    })
  end

  @doc "Record a species row as `failed` (retries exhausted). Broadcasts the full row."
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
        Logger.debug("SpeciesEnrichmentRuns: row #{tracking_id} missing, skipping finalize")
        nil

      %Run{} = run ->
        run
        |> Run.changeset(attrs)
        |> Repo.update!()
        |> Repo.preload(:species)
        |> broadcast_run()
    end
  end

  defp broadcast_run(%Run{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, @topic, {:enrichment_run, run})
    run
  end

  # ── Reads ────────────────────────────────────────────────────────────────────

  @doc "The `batch_id` of the most recently started batch, or nil."
  def latest_batch_id do
    Repo.one(
      from(r in Run, order_by: [desc: r.inserted_at, desc: r.id], limit: 1, select: r.batch_id)
    )
  end

  @doc "All tracking rows for a batch (species preloaded), species-name ordered."
  def list_batch_rows(nil), do: []

  def list_batch_rows(batch_id) do
    Repo.all(
      from(r in Run,
        join: s in assoc(r, :species),
        where: r.batch_id == ^batch_id,
        order_by: [asc: s.name, asc: s.variety],
        preload: [species: s]
      )
    )
  end

  @doc """
  Aggregate progress for a batch: a `%{pending, processing, completed, failed, total,
  facts_total}` summary derived by counting over `batch_id` (`facts_total` = Wikidata +
  FAOSTAT facts upserted across the batch).
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
        from(r in Run,
          where: r.batch_id == ^batch_id,
          select: coalesce(sum(r.wikidata_count), 0) + coalesce(sum(r.faostat_count), 0)
        )
      )

    %{
      pending: Map.get(by_status, "pending", 0),
      processing: Map.get(by_status, "processing", 0),
      completed: Map.get(by_status, "completed", 0),
      failed: Map.get(by_status, "failed", 0),
      total: by_status |> Map.values() |> Enum.sum(),
      facts_total: facts_total
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
  Cancel a batch: cancel its remaining Oban jobs, then mark any still-unfinished rows
  `failed` ("cancelled by admin"). Already-fetched facts are kept.
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
      set: [status: "failed", error: "cancelled by admin", completed_at: now(), updated_at: now()]
    )

    :cancelled
  end

  defp empty_counts,
    do: %{pending: 0, processing: 0, completed: 0, failed: 0, total: 0, facts_total: 0}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
