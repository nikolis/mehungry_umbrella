defmodule Mehungry.AI.RecipeMealRoleClassifierBehaviour do
  @moduledoc """
  Seam for the recipe meal-role classifier so tests can stub it (config key
  `:meal_role_classifier`), mirroring `:taxonomy_classifier`.
  """

  @doc """
  Classifies recipes into meal roles (`Mehungry.Food.MealRoles`), several per recipe.

    * `recipes` — the maps built by `MealRoleAssignments.classifier_inputs/1`
      (at least `:id` and `:title`)

  Returns `{:ok, %{recipe_id => [%{role: String.t(), confidence: float | nil}]}}`
  (recipes the model skipped may be absent) or `{:error, term}`.
  """
  @callback classify(recipes :: [map()]) :: {:ok, map()} | {:error, term()}
end
