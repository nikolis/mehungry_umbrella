defmodule Mehungry.Food.Nutrients do
  @moduledoc """
  Nutrient records, key-nutrient listings, nutrient interactions, and
  recalculation job enqueueing. (Plural module name to avoid clashing with
  the `Mehungry.Food.Nutrient` schema.)
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Nutrient, NutrientInteractions, Recipes}
  alias Mehungry.Food.NutrientRecalculationRuns

  def get_nutrient(id) do
    if not is_nil(id) and id != "" do
      query = from nutr in Nutrient, where: nutr.id == ^id

      Repo.one(query)
      |> Repo.preload(:measurement_unit)
    else
      nil
    end
  end

  def get_nutrient(name, measurment_unit_id) do
    query =
      from nutr in Nutrient,
        where:
          nutr.name == ^name and
            nutr.measurement_unit_id == ^measurment_unit_id

    Repo.one(query)
  end

  def create_nutrient(attrs) do
    %Nutrient{}
    |> Nutrient.changeset(attrs)
    |> Repo.insert()
  end

  def list_nutrients() do
    Repo.all(Mehungry.Food.Nutrient)
  end

  def list_key_nutrients() do
    Repo.all(from n in Mehungry.Food.Nutrient, order_by: [asc: n.rank], limit: 30)
  end

  def enqueue_nutrient_recalculation_for_all do
    ids = Recipes.list_recipe_ids()

    Enum.each(ids, fn id ->
      %{recipe_id: id}
      |> Mehungry.RecipePutNutrientsWorker.new()
      |> Oban.insert()
    end)

    length(ids)
  end

  @doc """
  Recompute nutrients for every recipe as a tracked batch: opens a
  `NutrientRecalculationRun`, enqueues one `RecipePutNutrientsWorker` per recipe
  (each carrying the `run_id` so it reports its outcome back), and returns the
  run so the caller can render live progress. See
  `Mehungry.Food.NutrientRecalculationRuns`.
  """
  def start_full_recalculation_run do
    ids = Recipes.list_recipe_ids()
    run = NutrientRecalculationRuns.start_run(length(ids))

    Enum.each(ids, fn id ->
      %{recipe_id: id, run_id: run.id}
      |> Mehungry.RecipePutNutrientsWorker.new()
      |> Oban.insert()
    end)

    run
  end

  def get_interactions_for_ingredients(ingredient_ids) do
    Mehungry.Food.NutrientInteractions.interactions_for_ingredients(ingredient_ids)
  end

  @doc """
  Nutrient interactions for a recipe, derived from its ingredients.

  Uses the same per-ingredient path as the food-detail page
  (`interactions_for_ingredients/1`), which classifies each ingredient's
  significant nutrients directly from the DB. This is the only correct source:
  the interaction rules key on individual vitamins/minerals (Iron, Vitamin C,
  …) which are nested as children in the recipe's hierarchical `nutrients` map,
  so summing that map's top-level entries would never surface them.

  Requires `recipe_ingredients` to be preloaded; returns `[]` otherwise.
  """
  def get_interactions_for_recipe(recipe) do
    ingredient_ids =
      case Map.get(recipe, :recipe_ingredients) do
        ingredients when is_list(ingredients) ->
          ingredients
          |> Enum.map(&Map.get(&1, :ingredient_id))
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end

    NutrientInteractions.interactions_for_ingredients(ingredient_ids)
  end

  def enqueue_interaction_recalculation_for_all do
    enqueue_nutrient_recalculation_for_all()
  end
end
