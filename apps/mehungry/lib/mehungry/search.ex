defmodule Mehungry.Search do
  alias Mehungry.Search.RecipeSearch

  def change_recipe_search(%RecipeSearch{} = recipe_search, attrs \\ %{}) do
    RecipeSearch.changeset(recipe_search, attrs)
  end

  def search_recipe(%RecipeSearch{} = recipe_search) do
    # TODO Search for recipes in here
  end
end
