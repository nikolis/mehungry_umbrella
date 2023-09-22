defmodule Mehungry.FoodTest do
  use Mehungry.DataCase

  alias Mehungry.History.{UserMeal}
  alias Mehungry.History
  alias Mehungry.Food 
  import Mehungry.{FoodFixtures, AccountsFixtures}

  @invalid_params_recipe %{servings: nil, title: nil, recipe_ingredients: []}
  @create_params_recipe %{servings: 3, title: "Title Recipe" , language_name: "En"}

  defp create_user(_) do 
    user = user_fixture()
    %{user: user}
  end

  defp create_ingredient(_) do
    ingredient = ingredient_fixture()
    %{ingredient: ingredient}
  end

  defp create_measurement_unit(_) do
    measurement_unit = measurement_unit_fixture()
    %{measurement_unit: measurement_unit}
  end


  describe "Recipe Tests" do
    setup [:create_user, :create_ingredient, :create_measurement_unit]

    test "Test Create Recipe Valid arguments", %{ingredient: ingredient, measurement_unit: measurement_unit} do
      
      ingredients = [%{ingredient_id: ingredient.id, measurement_unit_id: measurement_unit.id, quantity: 33}]

      recipe_params = 
        @create_params_recipe
        |> Enum.into(%{recipe_ingredients: ingredients})

      assert {:ok, _recipe} = Food.create_recipe(recipe_params) 
    end


    test "Create Recipe with invalid arguments should provide feedback", %{ingredient: ingredient, measurement_unit: measurement_unit} do
      
      ingredients = [%{ingredient_id: ingredient.id, measurement_unit_id: measurement_unit.id, quantity: 33}]

      recipe_params = 
        @invalid_params_recipe
        |> Enum.into(%{recipe_ingredients: ingredients})


      assert {:error, changeset} = Food.create_recipe(recipe_params) 
      assert changeset.errors == [{:recipe_ingredients, {"can't be blank", [validation: :required]}}, {:title, {"can't be blank", [validation: :required]}}, {:language_name, {"can't be blank", [validation: :required]}}] 
    end


    test "Test Update Recipe Valid arguments", %{user: user} do
      

      recipe = recipe_fixture(user)
      assert {:ok, new_recipe} = Food.update_recipe(recipe, %{title: "New recipe title"})
      recipe_test = Food.get_recipe!(recipe.id)
      assert recipe_test.title == new_recipe.title

    end


    test "Test Update Recipe Invalid arguments", %{user: user} do
      
      recipe = recipe_fixture(user)
      assert {:error, changeset} = Food.update_recipe(recipe, %{recipe_ingredients: []})
      assert changeset.errors == [{:recipe_ingredients, {"can't be blank", [validation: :required]}}] 
   end

  end



  describe "User Meal Test" do
    setup [:create_user]

    test "Create User Meal", %{user: user} do
      recipe = recipe_fixture(user)
      dt_now = NaiveDateTime.utc_now()

      user_meal_params = %{
        start_dt: dt_now,
        end_dt: dt_now,
        title: "Breakfast",
        user_id: user.id,
        recipe_user_meals: [%{recipe_id: recipe.id}]
      }

      assert {:ok, %UserMeal{} = _user_meal} = History.create_user_meal(user_meal_params)
    end
  end
 
end
