defmodule Mehungry.Food.RecipesAdminTest do
  use Mehungry.DataCase

  alias Mehungry.Food
  alias Mehungry.Food.RecipeIngredient
  alias Mehungry.Repo

  import Mehungry.{FoodFixtures, AccountsFixtures}

  # The recipe changeset requires ingredients, so build a normal recipe then
  # strip its RecipeIngredient rows to model an "empty" recipe.
  defp empty_recipe(user) do
    recipe = recipe_fixture(user)
    Repo.delete_all(from(ri in RecipeIngredient, where: ri.recipe_id == ^recipe.id))
    recipe
  end

  describe "delete_recipes_without_ingredients/0" do
    setup do
      %{user: user_fixture()}
    end

    test "deletes only recipes with zero ingredients", %{user: user} do
      kept = recipe_fixture(user)
      empty = empty_recipe(user)

      assert Food.count_recipes_without_ingredients() == 1

      assert {:ok, 1} = Food.delete_recipes_without_ingredients()

      assert Repo.get(Mehungry.Food.Recipe, empty.id) == nil
      assert Repo.get(Mehungry.Food.Recipe, kept.id) != nil
      assert Food.count_recipes_without_ingredients() == 0
    end

    test "is a no-op when every recipe has ingredients", %{user: user} do
      recipe_fixture(user)

      assert Food.count_recipes_without_ingredients() == 0
      assert {:ok, 0} = Food.delete_recipes_without_ingredients()
    end

    test "lists recipes with zero ingredients", %{user: user} do
      _kept = recipe_fixture(user)
      empty = empty_recipe(user)

      ids = Food.list_recipes_without_ingredients() |> Enum.map(& &1.id)

      assert ids == [empty.id]
    end
  end
end
