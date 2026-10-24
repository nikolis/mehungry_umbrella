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

  @doc """
  Maps each nutrient `name` to a short unit label (e.g. "mg", "µg", "g") via its
  `measurement_unit`. A name with several units resolves to the first found.
  """
  def nutrient_unit_labels(names) when is_list(names) do
    names = Enum.uniq(names)

    if names == [] do
      %{}
    else
      from(n in Nutrient,
        join: mu in assoc(n, :measurement_unit),
        where: n.name in ^names,
        select: {n.name, mu.name}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {name, unit}, acc -> Map.put_new(acc, name, unit_label(unit)) end)
    end
  end

  def nutrient_unit_labels(_), do: %{}

  @doc """
  Like `nutrient_unit_labels/1`, but resolves each requested *canonical* label
  (e.g. "Fiber", "Omega-3") against raw USDA `Nutrient.name`s run through
  `NutrientNameNormalizer.normalize/1` — so a label that never appears verbatim
  in the table (the common case for blueprint goals) still gets a unit. One query
  over nutrients that carry a measurement unit.
  """
  def nutrient_unit_labels_normalized(labels) when is_list(labels) do
    wanted = labels |> Enum.uniq() |> MapSet.new()

    if MapSet.size(wanted) == 0 do
      %{}
    else
      from(n in Nutrient,
        join: mu in assoc(n, :measurement_unit),
        select: {n.name, mu.name}
      )
      |> Repo.all()
      |> Enum.reduce(%{}, fn {name, unit}, acc ->
        canonical = Mehungry.Food.NutrientNameNormalizer.normalize(name)

        if MapSet.member?(wanted, canonical) and not Map.has_key?(acc, canonical),
          do: Map.put(acc, canonical, unit_label(unit)),
          else: acc
      end)
    end
  end

  def nutrient_unit_labels_normalized(_), do: %{}

  defp unit_label("gram"), do: "g"
  defp unit_label("milligram"), do: "mg"
  defp unit_label("microgram"), do: "µg"
  defp unit_label("mcg"), do: "µg"
  defp unit_label("kilocalorie"), do: "kcal"
  defp unit_label("kilojoule"), do: "kJ"
  defp unit_label("kj"), do: "kJ"
  defp unit_label("International Unit"), do: "IU"
  defp unit_label("iu"), do: "IU"
  defp unit_label(other), do: other

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
