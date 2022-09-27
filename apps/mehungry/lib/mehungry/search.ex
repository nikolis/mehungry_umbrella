defmodule Mehungry.Search do
  alias Mehungry.Search.RecipeSearch

  def change_recipe_search(%RecipeSearch{} = recipe_search, attrs \\ %{}) do
    RecipeSearch.changeset(recipe_search, attrs)
  end

  def update_recipe_search(%RecipeSearch{} = recipe_search, attrs \\ %{}) do
    changeset = RecipeSearch.changeset(recipe_search, attrs)

    if !changeset.valid? do
      {:error, changeset}
    else
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    end
  end
end
