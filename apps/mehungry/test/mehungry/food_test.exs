defmodule Mehungry.FoodTest do
  use Mehungry.DataCase

  alias Mehungry.History.{UserMeal}
  alias Mehungry.History
  alias Mehungry.Food
  import Mehungry.{FoodFixtures, AccountsFixtures}

  @invalid_params_recipe %{servings: nil, title: nil, recipe_ingredients: []}
  @create_params_recipe %{servings: 3, title: "Title Recipe", language_name: "En"}

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

    test "Test Create Recipe Valid arguments", %{
      ingredient: ingredient,
      measurement_unit: measurement_unit,
      user: user
    } do
      ingredients = [
        %{ingredient_id: ingredient.id, measurement_unit_id: measurement_unit.id, quantity: 33}
      ]

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{recipe_ingredients: ingredients, user_id: user.id})

      assert {:ok, _recipe} = Food.create_recipe(recipe_params)
    end

    test "Create Recipe with invalid arguments should provide feedback", %{
      ingredient: ingredient,
      measurement_unit: measurement_unit
    } do
      ingredients = [
        %{ingredient_id: ingredient.id, measurement_unit_id: measurement_unit.id, quantity: 33}
      ]

      recipe_params =
        @invalid_params_recipe
        |> Enum.into(%{recipe_ingredients: ingredients})

      assert {:error, changeset} = Food.create_recipe(recipe_params)

      assert changeset.errors == [
               {:recipe_ingredients, {"can't be blank", [validation: :required]}},
               {:title, {"can't be blank", [validation: :required]}},
               {:language_name, {"can't be blank", [validation: :required]}},
               {:user_id, {"can't be blank", [validation: :required]}}
             ]
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

      assert changeset.errors == [
               {:recipe_ingredients, {"can't be blank", [validation: :required]}}
             ]
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
        consume_portions: 3,
        cooking_portions: 5,
        user_id: user.id,
        recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 3, cooking_portions: 5}]
      }

      assert {:ok, %UserMeal{} = _user_meal} = History.create_user_meal(user_meal_params)
    end
  end

  describe "food_restriction_types" do
    alias Mehungry.Food.FoodRestrictionType

    import Mehungry.FoodFixtures

    @invalid_attrs %{alias: nil, title: nil}

    test "list_food_restriction_types/0 returns all food_restriction_types" do
      food_restriction_type = food_restriction_type_fixture()
      assert Food.list_food_restriction_types() == [food_restriction_type]
    end

    test "get_food_restriction_type!/1 returns the food_restriction_type with given id" do
      food_restriction_type = food_restriction_type_fixture()
      assert Food.get_food_restriction_type!(food_restriction_type.id) == food_restriction_type
    end

    test "create_food_restriction_type/1 with valid data creates a food_restriction_type" do
      valid_attrs = %{alias: "some alias", title: "some title"}

      assert {:ok, %FoodRestrictionType{} = food_restriction_type} =
               Food.create_food_restriction_type(valid_attrs)

      assert food_restriction_type.alias == "some alias"
      assert food_restriction_type.title == "some title"
    end

    test "create_food_restriction_type/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Food.create_food_restriction_type(@invalid_attrs)
    end

    test "update_food_restriction_type/2 with valid data updates the food_restriction_type" do
      food_restriction_type = food_restriction_type_fixture()
      update_attrs = %{alias: "some updated alias", title: "some updated title"}

      assert {:ok, %FoodRestrictionType{} = food_restriction_type} =
               Food.update_food_restriction_type(food_restriction_type, update_attrs)

      assert food_restriction_type.alias == "some updated alias"
      assert food_restriction_type.title == "some updated title"
    end

    test "update_food_restriction_type/2 with invalid data returns error changeset" do
      food_restriction_type = food_restriction_type_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Food.update_food_restriction_type(food_restriction_type, @invalid_attrs)

      assert food_restriction_type == Food.get_food_restriction_type!(food_restriction_type.id)
    end

    test "delete_food_restriction_type/1 deletes the food_restriction_type" do
      food_restriction_type = food_restriction_type_fixture()

      assert {:ok, %FoodRestrictionType{}} =
               Food.delete_food_restriction_type(food_restriction_type)

      assert_raise Ecto.NoResultsError, fn ->
        Food.get_food_restriction_type!(food_restriction_type.id)
      end
    end

    test "change_food_restriction_type/1 returns a food_restriction_type changeset" do
      food_restriction_type = food_restriction_type_fixture()
      assert %Ecto.Changeset{} = Food.change_food_restriction_type(food_restriction_type)
    end
  end
end
