defmodule Mehungry.ObanWorkers.TaxonomyClassificationWorker do
  @moduledoc """
  Classifies ingredients into a taxonomy's leaf nodes in batches, re-enqueueing
  itself until every ingredient has a mapping (mirrors
  `Mehungry.IngredientTranslationWorker`).

  Termination is guaranteed by two mechanisms: the seeded "Other / Unclassified"
  fallback leaf means the AI can always place an ingredient somewhere, and a
  batch that produces zero inserts stops the chain instead of re-enqueueing.
  """

  use Oban.Worker, queue: :ai_agents, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Mehungry.Food.{IngredientTaxonomyNode, Taxonomies}
  alias Mehungry.Repo

  @batch_size 40

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"taxonomy_id" => taxonomy_id}}) do
    batch = fetch_unclassified_batch(taxonomy_id)

    case batch do
      [] ->
        Logger.info(
          "[TaxonomyClassificationWorker] all ingredients classified for taxonomy #{taxonomy_id}"
        )

        :ok

      ingredients ->
        leaves = Taxonomies.list_leaf_paths(taxonomy_id)

        Logger.info(
          "[TaxonomyClassificationWorker] classifying batch of #{length(ingredients)} " <>
            "into #{length(leaves)} leaves (taxonomy #{taxonomy_id})"
        )

        case classifier().classify(ingredients, leaves) do
          {:ok, assignments} ->
            handle_assignments(taxonomy_id, assignments, leaves)

          {:error, reason} ->
            Logger.warning(
              "[TaxonomyClassificationWorker] classification failed: #{inspect(reason)}"
            )

            {:error, reason}
        end
    end
  end

  def enqueue(taxonomy_id) do
    %{taxonomy_id: taxonomy_id}
    |> new()
    |> Oban.insert()
  end

  defp handle_assignments(taxonomy_id, assignments, leaves) do
    slug_to_node_id = Map.new(leaves, fn %{slug: slug, id: id} -> {slug, id} end)
    inserted = insert_assignments(assignments, slug_to_node_id)

    if inserted > 0 do
      Logger.info("[TaxonomyClassificationWorker] inserted #{inserted} mappings")
      enqueue(taxonomy_id)
      :ok
    else
      Logger.warning(
        "[TaxonomyClassificationWorker] batch produced no usable assignments, " <>
          "stopping to avoid a retry loop (taxonomy #{taxonomy_id})"
      )

      :ok
    end
  end

  defp fetch_unclassified_batch(taxonomy_id) do
    taxonomy_id
    |> Taxonomies.unclassified_ingredients_query()
    |> order_by([i], asc: i.id)
    |> limit(@batch_size)
    |> select([i], %{id: i.id, name: i.name})
    |> Repo.all()
  end

  defp insert_assignments(assignments, slug_to_node_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.flat_map(assignments, fn {ingredient_id, %{slug: slug, confidence: confidence}} ->
        case Map.get(slug_to_node_id, slug) do
          nil ->
            []

          node_id ->
            [
              %{
                ingredient_id: ingredient_id,
                taxonomy_node_id: node_id,
                source: "ai",
                confidence: confidence,
                reviewed: false,
                inserted_at: now,
                updated_at: now
              }
            ]
        end
      end)

    {count, _} =
      Repo.insert_all(IngredientTaxonomyNode, rows,
        on_conflict: :nothing,
        conflict_target: [:ingredient_id, :taxonomy_node_id]
      )

    count
  end

  defp classifier do
    Application.get_env(:mehungry, :taxonomy_classifier, Mehungry.AI.TaxonomyClassifier)
  end
end
