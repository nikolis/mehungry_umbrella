defmodule MehungryWeb.RecipeFlags do
  @moduledoc """
  Display-time enrichment of recipes with health-condition badges for the
  viewing user. Batch-loads `Mehungry.Health.flags_for_recipes/2` for the
  user's opted-in conditions and stamps each recipe's virtual
  `:condition_flags` field, so `RecipeComponents.recipe_card` / `recipe_details`
  can render badges without per-card queries.

  All functions no-op (return the recipes untouched, flags stay `[]`) when the
  user has not opted into any condition, so non-opted-in users never hit the DB.
  """

  alias Mehungry.Accounts
  alias Mehungry.Health

  @doc "The condition ids a profile has opted into, or `[]` for `nil`."
  def opted_in_condition_ids(nil), do: []

  def opted_in_condition_ids(%{id: profile_id}),
    do: Accounts.list_opted_in_condition_ids(profile_id)

  @doc """
  Stamps `:condition_flags` on each recipe in `recipes` for the given opted-in
  `condition_ids`. Returns the recipes unchanged when `condition_ids` is empty.
  """
  def enrich(recipes, condition_ids)

  def enrich(recipes, []), do: recipes

  def enrich(recipes, condition_ids) do
    flags_by_recipe =
      recipes
      |> Enum.map(& &1.id)
      |> Health.flags_for_recipes(condition_ids)

    Enum.map(recipes, fn recipe ->
      %{recipe | condition_flags: Map.get(flags_by_recipe, recipe.id, [])}
    end)
  end

  @doc "Enrich a single recipe."
  def enrich_one(recipe, []), do: recipe

  def enrich_one(recipe, condition_ids) do
    %{recipe | condition_flags: Health.flags_for_recipe(recipe.id, condition_ids)}
  end

  @doc """
  Condition badges keyed by ingredient id, for the viewer's opted-in
  `condition_ids`. Delegates to `Health.flags_for_ingredients/2`; returns `%{}`
  cheaply for a non-opted-in user (empty `condition_ids`), so any ingredient
  surface (search dropdown, calendar entry, recipe ingredient list) can look up
  `Map.get(flags, ingredient_id, [])` and render `condition_flag_badges`.
  """
  def flags_for_ingredient_ids(ingredient_ids, condition_ids),
    do: Health.flags_for_ingredients(ingredient_ids, condition_ids)
end
