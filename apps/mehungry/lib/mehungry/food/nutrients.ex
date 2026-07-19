defmodule Mehungry.Food.Nutrients do
  @moduledoc """
  Nutrient records, key-nutrient listings, nutrient interactions, and
  recalculation job enqueueing. (Plural module name to avoid clashing with
  the `Mehungry.Food.Nutrient` schema.)
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food.{Nutrient, NutrientInteractions, NutrientMerger, Recipes}

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

  def get_interactions_for_ingredients(ingredient_ids) do
    Mehungry.Food.NutrientInteractions.interactions_for_ingredients(ingredient_ids)
  end

  def get_interactions_for_recipe(recipe) do
    stored = Map.get(recipe, :ingredient_interactions, [])

    if is_list(stored) and stored != [] do
      Enum.map(stored, &atomize_interaction/1)
    else
      nutrients = recipe.nutrients || %{}

      if map_size(nutrients) == 0 do
        []
      else
        nutrient_map =
          Enum.reduce(nutrients, %{}, fn {name, data}, acc ->
            amount = Map.get(data, "amount") || Map.get(data, :amount) || 0.0
            canonical = NutrientMerger.normalize_nutrient_name(name)
            Map.update(acc, canonical, amount, &(&1 + amount))
          end)

        NutrientInteractions.interactions_for_nutrient_map(nutrient_map)
      end
    end
  end

  def enqueue_interaction_recalculation_for_all do
    enqueue_nutrient_recalculation_for_all()
  end

  defp atomize_interaction(i) do
    %{
      id: Map.get(i, "id", "") |> safe_to_atom(),
      type: Map.get(i, "type", "") |> safe_to_atom(),
      badge: Map.get(i, "badge", "tip") |> safe_to_atom(),
      label: Map.get(i, "label", ""),
      detail: Map.get(i, "detail", ""),
      source: Map.get(i, "source", ""),
      nutrient_a: Map.get(i, "nutrient_a"),
      nutrient_b: Map.get(i, "nutrient_b")
    }
  end

  defp safe_to_atom(str) when is_binary(str), do: String.to_existing_atom(str)
  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
