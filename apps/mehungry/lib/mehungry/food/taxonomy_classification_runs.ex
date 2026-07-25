defmodule Mehungry.Food.TaxonomyClassificationRuns do
  @moduledoc """
  Query/command layer for `Mehungry.Food.TaxonomyClassificationRun` — the durable
  tracking rows behind the taxonomy classification flow.

  Every status transition broadcasts the updated row on `Mehungry.PubSub` under
  `topic(taxonomy_id)`, so `MehungryWeb.ProfessionalLive.TaxonomyReview` can render
  a live progress bar without a manual refresh. Mirrors
  `Mehungry.FoodData.Usda.SeedFiles`.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.Food.TaxonomyClassificationRun
  alias Mehungry.Food.Taxonomies
  alias Mehungry.Repo

  @doc "PubSub topic carrying `{:classification_run, %TaxonomyClassificationRun{}}` updates."
  def topic(taxonomy_id), do: "taxonomy_classification:#{taxonomy_id}"

  @doc """
  Inserts a fresh `pending` run row for a taxonomy, seeded with the current
  coverage snapshot and `started_at`. Broadcasts and returns the row.
  """
  def start_run(taxonomy_id) do
    %{classified: classified, total: total} = Taxonomies.classification_progress(taxonomy_id)

    {:ok, run} =
      %TaxonomyClassificationRun{}
      |> TaxonomyClassificationRun.changeset(%{
        taxonomy_id: taxonomy_id,
        status: "pending",
        classified: classified,
        total: total,
        error: nil,
        started_at: now(),
        completed_at: nil
      })
      |> Repo.insert(returning: true)

    broadcast(run)
    run
  end

  def mark_processing(run_id), do: update_status(run_id, %{status: "processing"})

  def update_progress(run_id, %{classified: classified, total: total}) do
    update_status(run_id, %{classified: classified, total: total})
  end

  def mark_completed(run_id, %{classified: classified, total: total}) do
    update_status(run_id, %{
      status: "completed",
      classified: classified,
      total: total,
      error: nil,
      completed_at: now()
    })
  end

  def mark_failed(run_id, reason) do
    update_status(run_id, %{status: "failed", error: inspect(reason)})
  end

  @doc "The most recent run row for a taxonomy, or nil."
  def latest_run(taxonomy_id) do
    Repo.one(
      from r in TaxonomyClassificationRun,
        where: r.taxonomy_id == ^taxonomy_id,
        order_by: [desc: r.inserted_at, desc: r.id],
        limit: 1
    )
  end

  # Tolerant of a missing row so a stray update (e.g. a job outliving its run row)
  # is a no-op rather than a crash into pointless retries — same rationale as
  # `SeedFiles.update_status/2`.
  defp update_status(nil, _attrs), do: nil

  defp update_status(run_id, attrs) do
    case Repo.get(TaxonomyClassificationRun, run_id) do
      nil ->
        Logger.info("[TaxonomyClassificationRuns] update_status skipped — run ##{run_id} is gone")
        nil

      run ->
        run =
          run
          |> TaxonomyClassificationRun.changeset(attrs)
          |> Repo.update!()

        broadcast(run)
        run
    end
  end

  defp broadcast(%TaxonomyClassificationRun{} = run) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, topic(run.taxonomy_id), {:classification_run, run})
    run
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
