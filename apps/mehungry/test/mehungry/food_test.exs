defmodule Mehungry.FoodTest do
  use Mehungry.DataCase

  alias Mehungry.History.{UserMeal}
  alias Mehungry.History
  alias Mehungry.Food
  import Mehungry.{FoodFixtures, AccountsFixtures}

  @invalid_params_recipe %{
    servings: nil,
    title: nil,
    recipe_ingredients: [],
    difficulty: 1,
    cooking_time_lower_limit: 5,
    preperation_time_lower_limit: 5
  }
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
        |> Enum.into(%{
          recipe_ingredients: ingredients,
          user_id: user.id,
          cooking_time_lower_limit: 15,
          preperation_time_lower_limit: 15,
          difficulty: 1,
          description: "#greek_cusine"
          # recipe_hashtags: [%{hashtag: %{title: "greek_cusine"}}]
        })

      result = Food.create_recipe(recipe_params)
      {:ok, recipe} = result
      _recipe = Food.get_recipe_no_caching!(recipe.id)
      # assert _recipe = Food.create_recipe(recipe_params)
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

    test "non-gram recipe ingredient resolves ingredient_portion_id from its unit", %{
      ingredient: ingredient,
      user: user
    } do
      cup = measurement_unit_fixture(%{name: "cup"})

      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          measurement_unit_id: cup.id,
          gram_weight: 240.0,
          amount: 1.0
        })

      ingredients = [%{ingredient_id: ingredient.id, measurement_unit_id: cup.id, quantity: 2}]

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{
          recipe_ingredients: ingredients,
          user_id: user.id,
          cooking_time_lower_limit: 15,
          preperation_time_lower_limit: 15,
          difficulty: 1,
          description: "portion linkage"
        })

      assert {:ok, recipe} = Food.create_recipe(recipe_params)
      recipe = Food.get_recipe_no_caching!(recipe.id)
      assert [ri] = recipe.recipe_ingredients
      assert ri.ingredient_portion_id == portion.id
    end

    test "gram-family recipe ingredient leaves ingredient_portion_id nil", %{
      ingredient: ingredient,
      measurement_unit: gram_unit,
      user: user
    } do
      ingredients = [
        %{ingredient_id: ingredient.id, measurement_unit_id: gram_unit.id, quantity: 100}
      ]

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{
          recipe_ingredients: ingredients,
          user_id: user.id,
          cooking_time_lower_limit: 15,
          preperation_time_lower_limit: 15,
          difficulty: 1,
          description: "gram linkage"
        })

      assert {:ok, recipe} = Food.create_recipe(recipe_params)
      recipe = Food.get_recipe_no_caching!(recipe.id)
      assert [ri] = recipe.recipe_ingredients
      assert is_nil(ri.ingredient_portion_id)
    end

    test "updating a recipe re-resolves ingredient_portion_id", %{
      ingredient: ingredient,
      measurement_unit: gram_unit,
      user: user
    } do
      cup = measurement_unit_fixture(%{name: "cup"})

      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          measurement_unit_id: cup.id,
          gram_weight: 240.0,
          amount: 1.0
        })

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{
          recipe_ingredients: [
            %{ingredient_id: ingredient.id, measurement_unit_id: cup.id, quantity: 2}
          ],
          user_id: user.id,
          cooking_time_lower_limit: 15,
          preperation_time_lower_limit: 15,
          difficulty: 1,
          description: "reresolve"
        })

      assert {:ok, recipe} = Food.create_recipe(recipe_params)
      recipe = Food.get_recipe_no_caching!(recipe.id)
      assert [ri] = recipe.recipe_ingredients
      assert ri.ingredient_portion_id == portion.id

      # Switch the same row to grams — the FK must clear back to nil.
      assert {:ok, _} =
               Food.update_recipe(recipe, %{
                 recipe_ingredients: [
                   %{
                     id: ri.id,
                     ingredient_id: ingredient.id,
                     measurement_unit_id: gram_unit.id,
                     quantity: 100
                   }
                 ]
               })

      updated = Food.get_recipe_no_caching!(recipe.id)
      assert [updated_ri] = updated.recipe_ingredients
      assert is_nil(updated_ri.ingredient_portion_id)
    end

    test "description-only portion selection persists via unit_selection and clears the unit", %{
      ingredient: ingredient,
      user: user
    } do
      {:ok, portion} =
        Food.create_ingredient_portion(%{
          ingredient_id: ingredient.id,
          gram_weight: 118.0,
          amount: 1.0,
          description: "1 medium"
        })

      ingredients = [
        %{ingredient_id: ingredient.id, unit_selection: -portion.id, quantity: 1}
      ]

      recipe_params =
        @create_params_recipe
        |> Enum.into(%{
          recipe_ingredients: ingredients,
          user_id: user.id,
          cooking_time_lower_limit: 15,
          preperation_time_lower_limit: 15,
          difficulty: 1,
          description: "desc-only"
        })

      assert {:ok, recipe} = Food.create_recipe(recipe_params)
      recipe = Food.get_recipe_no_caching!(recipe.id)
      assert [ri] = recipe.recipe_ingredients
      assert ri.ingredient_portion_id == portion.id
      assert is_nil(ri.measurement_unit_id)

      # unit_label falls back to the portion's free-text description; the
      # dropdown re-selection value is the -portion_id encoding.
      ri = %{ri | ingredient_portion: portion}
      assert Mehungry.Food.RecipeIngredient.unit_label(ri) == "1 medium"
      assert Mehungry.Food.RecipeIngredient.unit_selection_value(ri) == -portion.id
    end

    test "Test recipe search_hashtag", %{user: user} do
      _recipe = recipe_fixture(user, %{description: "some description with #hashtag"})
      _recipe2 = recipe_fixture(user, %{description: "some description"})
      result = Food.search_hashtag("hashtag")
      assert length(result.recipe_hashtags) == 1
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

  # Property-based: these hold against whatever categories the DB carries (the
  # test DB is seeded with the real category catalogue), without pinning ids.
  describe "diet_category_ids/2" do
    test "omnivore excludes nothing" do
      assert Food.diet_category_ids(:omnivore) == []
    end

    test "vegan is a superset of vegetarian (vegan additionally excludes dairy)" do
      veg = MapSet.new(Food.diet_category_ids(:vegetarian))
      vegan = MapSet.new(Food.diet_category_ids(:vegan))
      assert MapSet.subset?(veg, vegan)
    end

    test "the lactose flag is additive and deduped: vegetarian + lactose == vegan" do
      veg_lactose = Food.diet_category_ids(:vegetarian, [:lactose_intolerant])
      vegan = Food.diet_category_ids(:vegan)

      # vegan = vegetarian ∪ {dairy}, so adding the lactose (dairy) flag to the
      # vegetarian set yields exactly the vegan set — and stays deduped.
      assert Enum.sort(veg_lactose) == Enum.sort(vegan)
      assert veg_lactose == Enum.uniq(veg_lactose)
    end

    test "lactose flag alone yields at most the single dairy category, within the vegan set" do
      lactose = Food.diet_category_ids(:omnivore, [:lactose_intolerant])
      vegan = MapSet.new(Food.diet_category_ids(:vegan))

      assert length(lactose) <= 1
      assert MapSet.subset?(MapSet.new(lactose), vegan)
    end
  end
end
