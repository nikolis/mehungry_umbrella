defmodule Mehungry.Food.DietClassifier do
  @moduledoc """
  Deterministic vegan/vegetarian classification of a recipe from its ingredient
  **categories** — no AI, no per-ingredient dietary flag (none exists).

  A recipe is considered *vegan* when none of its ingredients fall into a
  vegan-excluded category (Meats/Fish/Poultry/Dairy/Pork/Sausages/Lamb/Beef),
  and *vegetarian* when none fall into a vegetarian-excluded category (same set
  minus Dairy). The excluded-category vocabulary is the very same one the profile
  diet presets write via `Mehungry.Food.Categories.diet_category_ids/2`, so the
  tags a recipe earns stay in sync with what a diet-restricted user filters on.

  Because the vegan-excluded set is a superset of the vegetarian-excluded set, a
  recipe with no vegan-excluded ingredients is also vegetarian, so `classify/1`
  returns `["vegan", "vegetarian"]` in that case.

  Conservative on unknowns: if the recipe has no ingredients, or **any**
  ingredient is missing a category, `classify/1` returns `[]` — we only assert a
  diet tag when we can see every ingredient's category.

  Expects the recipe to be preloaded with `recipe_ingredients: [ingredient: :category]`
  (only `ingredient.category_id` is read).
  """

  alias Mehungry.Food.Categories

  @doc """
  Returns the list of diet hashtag titles a recipe qualifies for:
  `["vegan", "vegetarian"]`, `["vegetarian"]`, or `[]`.
  """
  def classify(%{recipe_ingredients: recipe_ingredients}) when is_list(recipe_ingredients) do
    ingredients = Enum.map(recipe_ingredients, & &1.ingredient)

    cond do
      ingredients == [] ->
        []

      Enum.any?(ingredients, &missing_category?/1) ->
        []

      true ->
        category_ids = ingredients |> Enum.map(& &1.category_id) |> MapSet.new()
        vegan_excluded = MapSet.new(Categories.diet_category_ids(:vegan))
        vegetarian_excluded = MapSet.new(Categories.diet_category_ids(:vegetarian))

        cond do
          MapSet.disjoint?(category_ids, vegan_excluded) -> ["vegan", "vegetarian"]
          MapSet.disjoint?(category_ids, vegetarian_excluded) -> ["vegetarian"]
          true -> []
        end
    end
  end

  def classify(_), do: []

  defp missing_category?(nil), do: true
  defp missing_category?(%{category_id: nil}), do: true
  defp missing_category?(_), do: false
end
