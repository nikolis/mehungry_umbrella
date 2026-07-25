defmodule Mehungry.ObanWorkers.TaxonomyClassificationWorker do
  @moduledoc """
  Classifies ingredients into one taxonomy's leaves, one batch per run,
  self-re-enqueueing until every ingredient has a mapping — same shape as
  `Mehungry.IngredientTranslationWorker`.

  Termination:
    * empty batch → every ingredient is classified, stop.
    * non-empty batch with **zero** inserts → the classifier returned nothing
      usable; stop rather than loop forever on unclassifiable rows.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Mehungry.Food
  alias Mehungry.Food.{Ingredient, IngredientTaxonomyNode, TaxonomyClassificationRuns, TaxonomyNode}
  alias Mehungry.Repo

  @batch_size 40

  # Mappings the classifier is this confident about skip human review — they land
  # already `reviewed: true`, so they never surface in the TaxonomyReview queue.
  @auto_confirm_confidence 0.80

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"taxonomy_id" => taxonomy_id} = args}) do
    run_id = Map.get(args, "run_id")
    TaxonomyClassificationRuns.mark_processing(run_id)

    case fetch_unclassified_batch(taxonomy_id) do
      [] ->
        Logger.info("TaxonomyClassificationWorker: taxonomy #{taxonomy_id} fully classified")
        TaxonomyClassificationRuns.mark_completed(run_id, Food.classification_progress(taxonomy_id))
        :ok

      batch ->
        Logger.info(
          "TaxonomyClassificationWorker: classifying batch of #{length(batch)} for taxonomy #{taxonomy_id}"
        )

        leaves = Food.list_leaves_with_paths(taxonomy_id)

        case classifier().classify(batch, leaves) do
          {:ok, assignments} ->
            handle_assignments(taxonomy_id, run_id, batch, assignments)

          {:error, reason} ->
            Logger.warning(
              "TaxonomyClassificationWorker: classification failed: #{inspect(reason)}"
            )

            TaxonomyClassificationRuns.mark_failed(run_id, reason)
            {:error, reason}
        end
    end
  end

  defp handle_assignments(taxonomy_id, run_id, batch, assignments) do
    if insert_assignments(assignments) > 0 do
      TaxonomyClassificationRuns.update_progress(run_id, Food.classification_progress(taxonomy_id))
      enqueue_next_batch(taxonomy_id, run_id)
      :ok
    else
      # Non-empty batch but nothing usable came back — stop to avoid an
      # infinite refetch loop.
      Logger.warning(
        "TaxonomyClassificationWorker: batch of #{length(batch)} produced no mappings for " <>
          "taxonomy #{taxonomy_id}; halting"
      )

      TaxonomyClassificationRuns.mark_completed(run_id, Food.classification_progress(taxonomy_id))
      :ok
    end
  end

  defp fetch_unclassified_batch(taxonomy_id) do
    classified_ids =
      from(itn in IngredientTaxonomyNode,
        join: n in TaxonomyNode,
        on: n.id == itn.taxonomy_node_id,
        where: n.taxonomy_id == ^taxonomy_id,
        select: itn.ingredient_id
      )

    Repo.all(
      from(i in Ingredient,
        where:
          i.id not in subquery(classified_ids) and not is_nil(i.fdc_id) and i.fdc_id > 0,
        limit: @batch_size,
        select: %{id: i.id, name: i.name}
      )
    )
  end

  defp insert_assignments(assignments) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(assignments, fn %{ingredient_id: ing_id, taxonomy_node_id: node_id} = a ->
        confidence = Map.get(a, :confidence)

        %{
          ingredient_id: ing_id,
          taxonomy_node_id: node_id,
          source: "ai",
          confidence: confidence,
          reviewed: auto_confirm?(confidence),
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} =
      Repo.insert_all(IngredientTaxonomyNode, rows,
        on_conflict: :nothing,
        conflict_target: [:ingredient_id, :taxonomy_node_id]
      )

    count
  end

  # Guarded against a nil confidence: `nil > 0.80` is `true` under Elixir term
  # ordering, which would wrongly auto-confirm unscored mappings.
  defp auto_confirm?(confidence) when is_number(confidence), do: confidence > @auto_confirm_confidence
  defp auto_confirm?(_), do: false

  defp enqueue_next_batch(taxonomy_id, run_id) do
    %{"taxonomy_id" => taxonomy_id, "run_id" => run_id} |> new() |> Oban.insert!()
  end

  defp classifier do
    Application.get_env(:mehungry, :taxonomy_classifier, Mehungry.AI.TaxonomyClassifier)
  end
end
