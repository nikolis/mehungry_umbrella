defmodule MehungrySeasonality.Runs do
  @moduledoc """
  Lifecycle + progress tracking for the admin-triggered "Fetch <country>" sweep
  (`/professional/seasonality`).

  The sweep **fans out** one `MehungrySeasonality.Workers.FetchWorker` job per mapped
  species, tracked by one `Run` row per species grouped by `batch_id`. Each job
  advances its own row `pending → processing → completed | failed`. Every transition
  is broadcast on the shared PubSub under `topic/0`: a slim
  `{:seasonality_processing, batch_id, species_id}` on the high-frequency processing
  edge, and a full `{:seasonality_run, %Run{}}` (species attached) on a terminal
  transition. The Oban-UI-connected pattern
  (`docs/reference_architecture/oban_ui_connected_worker.md`).
  """

  import Ecto.Query, warn: false

  require Logger

  alias MehungrySeasonality.{Core, Countries, Mappings, Run}
  alias MehungrySeasonality.Workers.FetchWorker

  @topic "seasonality_runs"
  @worker "MehungrySeasonality.Workers.FetchWorker"

  @doc "PubSub topic carrying `{:seasonality_run, %Run{}}` + `{:seasonality_processing, …}`."
  def topic, do: @topic

  @doc """
  Start a fetch batch for a country: open one `pending` tracking row per mapped
  species and fan out one worker job each via a single `Oban.insert_all`.

  Returns `{:ok, batch_id}`, or `{:error, :unsupported_country | :already_running |
  :no_mappings}`.
  """
  def fetch_country(country) do
    cond do
      not Countries.supported?(country) -> {:error, :unsupported_country}
      batch_in_flight?(latest_batch_id(country)) -> {:error, :already_running}
      true -> fan_out(country, Mappings.mapped_species_ids())
    end
  end

  defp fan_out(_country, []), do: {:error, :no_mappings}

  defp fan_out(country, species_ids) do
    batch_id = Ecto.UUID.generate()
    # `timestamps()` columns are :naive_datetime; insert_all needs them explicit.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(species_ids, fn species_id ->
        %{
          batch_id: batch_id,
          foundemental_species_id: species_id,
          country: country,
          status: "pending",
          local_count: 0,
          import_count: 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_, inserted} = Core.repo().insert_all(Run, rows, returning: [:id, :foundemental_species_id])

    inserted
    |> Enum.map(fn run ->
      FetchWorker.new(%{
        "tracking_id" => run.id,
        "species_id" => run.foundemental_species_id,
        "country" => country,
        "batch_id" => batch_id
      })
    end)
    |> Oban.insert_all()

    {:ok, batch_id}
  end

  @doc "Mark a species row `processing` + broadcast the slim progress signal."
  def mark_processing(nil), do: nil

  def mark_processing(tracking_id) do
    from(r in Run, where: r.id == ^tracking_id and r.status == "pending")
    |> Core.repo().update_all(set: [status: "processing", started_at: now(), updated_at: now()])

    case Core.repo().get(Run, tracking_id) do
      nil ->
        nil

      %Run{} = run ->
        Phoenix.PubSub.broadcast(
          Core.pubsub(),
          @topic,
          {:seasonality_processing, run.batch_id, run.foundemental_species_id}
        )

        run
    end
  end

  @doc "Record a species row as `completed` with its per-source month counts. Broadcasts the full row."
  def mark_completed(nil, _counts), do: nil

  def mark_completed(tracking_id, %{} = counts) do
    update_terminal(tracking_id, %{
      status: "completed",
      local_count: Map.get(counts, :local, 0),
      import_count: Map.get(counts, :import, 0),
      error: nil,
      completed_at: now()
    })
  end

  @doc "Record a species row as `failed` (retries exhausted). Broadcasts the full row."
  def mark_failed(nil, _reason), do: nil

  def mark_failed(tracking_id, reason) do
    update_terminal(tracking_id, %{
      status: "failed",
      error: reason |> to_message() |> String.slice(0, 500),
      completed_at: now()
    })
  end

  defp update_terminal(tracking_id, attrs) do
    case Core.repo().get(Run, tracking_id) do
      nil ->
        Logger.debug("Seasonality.Runs: row #{tracking_id} missing, skipping finalize")
        nil

      %Run{} = run ->
        run =
          run
          |> Run.changeset(attrs)
          |> Core.repo().update!()
          |> attach_species()

        Phoenix.PubSub.broadcast(Core.pubsub(), @topic, {:seasonality_run, run})
        run
    end
  end

  # ── Reads ────────────────────────────────────────────────────────────────────

  @doc "The `batch_id` of the most recently started batch for a country, or nil."
  def latest_batch_id(country) do
    Core.repo().one(
      from(r in Run,
        where: r.country == ^country,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: 1,
        select: r.batch_id
      )
    )
  end

  @doc "All tracking rows for a batch (species attached), species-name ordered."
  def list_batch_rows(nil), do: []

  def list_batch_rows(batch_id) do
    from(r in Run, where: r.batch_id == ^batch_id)
    |> Core.repo().all()
    |> attach_species()
    |> Enum.sort_by(&{&1.species.name, &1.species.variety || ""})
  end

  @doc "Aggregate progress for a batch: `%{pending, processing, completed, failed, total}`."
  def counts_for_batch(nil), do: empty_counts()

  def counts_for_batch(batch_id) do
    by_status =
      Core.repo().all(
        from(r in Run,
          where: r.batch_id == ^batch_id,
          group_by: r.status,
          select: {r.status, count(r.id)}
        )
      )
      |> Map.new()

    %{
      pending: Map.get(by_status, "pending", 0),
      processing: Map.get(by_status, "processing", 0),
      completed: Map.get(by_status, "completed", 0),
      failed: Map.get(by_status, "failed", 0),
      total: by_status |> Map.values() |> Enum.sum()
    }
  end

  @doc "True while a batch still has `pending`/`processing` rows."
  def batch_in_flight?(nil), do: false

  def batch_in_flight?(batch_id) do
    Core.repo().exists?(
      from(r in Run, where: r.batch_id == ^batch_id and r.status in ["pending", "processing"])
    )
  end

  @doc """
  Cancel a batch: cancel its remaining Oban jobs, then mark any still-unfinished rows
  `failed` ("cancelled by admin"). Already-fetched data is kept.
  """
  def cancel_batch(nil), do: :noop

  def cancel_batch(batch_id) do
    Oban.cancel_all_jobs(
      from(j in Oban.Job,
        where: j.worker == @worker and fragment("args->>'batch_id' = ?", ^batch_id)
      )
    )

    from(r in Run, where: r.batch_id == ^batch_id and r.status in ["pending", "processing"])
    |> Core.repo().update_all(
      set: [status: "failed", error: "cancelled by admin", completed_at: now(), updated_at: now()]
    )

    :cancelled
  end

  # Attach the slim species map (display only) to one run or a list of runs.
  defp attach_species(%Run{} = run), do: [run] |> attach_species() |> hd()

  defp attach_species(runs) when is_list(runs) do
    species =
      runs |> Enum.map(& &1.foundemental_species_id) |> Enum.uniq() |> Core.species_by_ids()

    Enum.map(runs, fn run ->
      fallback = %{
        id: run.foundemental_species_id,
        name: "Species ##{run.foundemental_species_id}",
        variety: nil
      }

      %{run | species: Map.get(species, run.foundemental_species_id, fallback)}
    end)
  end

  defp to_message(reason) when is_binary(reason), do: reason
  defp to_message(reason), do: inspect(reason)

  defp empty_counts, do: %{pending: 0, processing: 0, completed: 0, failed: 0, total: 0}

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
