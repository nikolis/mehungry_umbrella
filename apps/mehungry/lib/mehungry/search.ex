defmodule Mehungry.Search do
  @moduledoc false

  alias Mehungry.Repo

  alias Mehungry.Search.RecipeSearchItem
  alias Mehungry.Search.RecipeSearch
  alias Mehungry.Food
  alias Mehungry.Food.Recipe

  def change_recipe_search_item(%RecipeSearchItem{} = recipe_search, attrs \\ %{}) do
    RecipeSearchItem.changeset(recipe_search, attrs)
  end

  def update_recipe_search_item(%RecipeSearchItem{} = recipe_search, attrs \\ %{}) do
    changeset = RecipeSearchItem.changeset(recipe_search, attrs)

    if changeset.valid? do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  def search_recipe(search_term, language_name \\ nil) do
    query = RecipeSearch.run(Recipe, search_term)

    results =
      Repo.all(query)
      |> Repo.preload([:recipe_ingredients, :user])

    Food.localize_recipes(results, language_name)
  end
end
