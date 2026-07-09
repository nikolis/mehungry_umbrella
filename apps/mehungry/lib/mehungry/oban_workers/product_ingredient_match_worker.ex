defmodule Mehungry.ObanWorkers.ProductIngredientMatchWorker do
  @moduledoc """
  Links imported food products to the closest ingredient in the local USDA
  database via pg_trgm `word_similarity`, so scanned products plug into the
  existing recipe/nutrition features.

  Same self-re-enqueueing batch shape as `Mehungry.IngredientTranslationWorker`:
  each run takes a batch of unmatched products (most complete records first),
  matches, and enqueues the next batch until none remain. Kicked off after a
  bulk import (`mix import.off_products --match`) or manually from iex.

  The threshold (#{0.55}) is deliberately stricter than search's 0.3 — a wrong
  nutrition link is worse than a missing one. Products that stay below it are
  marked `unmatched_reviewed` so they are not rescanned every run; the status
  field leaves room for a manual review UI. A future enhancement can push the
  unmatched tail through the existing `Mehungry.AI` client.
  """

  use Oban.Worker, queue: :imports, max_attempts: 3

  require Logger

  import Ecto.Query

  alias Mehungry.Food.Ingredient
  alias Mehungry.FoodProducts.FoodProduct
  alias Mehungry.FoodProducts.FoodProductTranslation
  alias Mehungry.Repo

  @batch_size 500
  @match_threshold 0.55

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case fetch_unmatched_batch() do
      [] ->
        Logger.info("[ProductIngredientMatch] all products processed")
        :ok

      batch ->
        Logger.info("[ProductIngredientMatch] matching batch of #{length(batch)}")

        Enum.each(batch, &match_product/1)
        enqueue_next_batch()
        :ok
    end
  end

  defp fetch_unmatched_batch do
    english_names =
      from t in FoodProductTranslation,
        where:
          fragment("lower(?)", t.language_name) == "en" and
            t.food_product_id == parent_as(:product).id,
        select: t.name,
        limit: 1

    Repo.all(
      from p in FoodProduct,
        as: :product,
        where: p.ingredient_match_status == "unmatched" or is_nil(p.ingredient_match_status),
        order_by: [desc_nulls_last: p.completeness, asc: p.id],
        limit: @batch_size,
        select: %{id: p.id, name: p.name, english_name: subquery(english_names)}
    )
  end

  defp match_product(%{id: id} = product) do
    name = product.english_name || product.name

    case best_ingredient_match(name) do
      {ingredient_id, score} when score >= @match_threshold ->
        update_product(id, %{
          ingredient_id: ingredient_id,
          ingredient_match_score: score,
          ingredient_match_status: "auto"
        })

      _ ->
        update_product(id, %{ingredient_match_status: "unmatched_reviewed"})
    end
  end

  defp best_ingredient_match(nil), do: nil

  defp best_ingredient_match(name) do
    Repo.one(
      from i in Ingredient,
        where: not is_nil(i.search_name),
        order_by: [
          desc: fragment("word_similarity(unaccent(?), unaccent(?))", ^name, i.search_name)
        ],
        limit: 1,
        select:
          {i.id, fragment("word_similarity(unaccent(?), unaccent(?))", ^name, i.search_name)}
    )
  end

  defp update_product(id, attrs) do
    updates =
      Enum.to_list(attrs) ++
        [updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]

    from(p in FoodProduct, where: p.id == ^id)
    |> Repo.update_all(set: updates)
  end

  defp enqueue_next_batch do
    %{} |> new() |> Oban.insert!()
  end
end
