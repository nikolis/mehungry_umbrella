defmodule MehungryApi.HistoryTest do
  use Mehungry.DataCase

  alias Mehungry.History
  alias Mehungry.FoodFixtures
  alias Mehungry.AccountsFixtures

  describe "history_user_meals" do
    alias Mehungry.History.UserMeal

    import Mehungry.HistoryFixtures

    setup do
      user = AccountsFixtures.user_fixture()

      %{user: user}
    end

    @invalid_attrs %{meal_datetime: nil, title: nil}

    test "list_pending_user_meals/0 returns all history_user_meals", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "other name 2"})
      recipe2 = FoodFixtures.recipe_fixture(user, %{name: "other naasfddffsda"})

      _user_meal =
        user_meal_fixture(%{
          user_id: user.id,
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 6, cooking_portions: 6}]
        })

      user_meal =
        user_meal_fixture(%{
          user_id: user.id,
          recipe_user_meals: [%{recipe_id: recipe2.id, consume_portions: 6, cooking_portions: 9}]
        })
        |> Mehungry.Repo.preload(:consume_recipe_user_meals)

      [result] = History.list_incomplete_user_meals2(user.id, nil)
      IO.inspect(History.get_available_portions_for_user_meal(result.id))
      re_user_meal = result

      # assert {:error, %{errors: [recipe_user_meal_id: {"This user meal has only 3 portions left"}]}} = History.update_user_meal(user_meal, %{consume_recipe_user_meals: [%{user_meal_id: user_meal.id, recipe_user_meal_id: re_user_meal.id, consume_portions: 4 }]}) 

      History.update_user_meal(user_meal, %{
        consume_recipe_user_meals: [
          %{user_meal_id: user_meal.id, recipe_user_meal_id: re_user_meal.id, consume_portions: 3}
        ]
      })

      result22 = History.list_incomplete_user_meals2(user.id, nil)

      assert result22 == []
    end

    test "list_history_user_meals/0 returns all history_user_meals", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user)

      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      user_meal = History.get_user_meal!(user_meal.id)
      assert History.list_history_user_meals() == [user_meal]
    end

    test "get_user_meal!/1 returns the user_meal with given id", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user)

      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      user_meal = History.get_user_meal!(user_meal.id)
      assert History.get_user_meal!(user_meal.id) == user_meal
    end

    test "create_user_meal/1 with valid data creates a user_meal" do
      user = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user)
      recipe_0 = FoodFixtures.recipe_fixture(user, %{name: "other name"})

      valid_attrs = %{
        start_dt: ~U[2022-02-13 16:50:00Z],
        title: "some title",
        user_id: user.id,
        recipe_user_meals: [
          %{cooking_portions: 2, consume_portions: 1, recipe_id: recipe_0.id},
          %{recipe_id: recipe.id, cooking_portions: 2, consume_portions: 1}
        ]
      }

      assert {:ok, %UserMeal{} = user_meal} = History.create_user_meal(valid_attrs)

      user_meal =
        Mehungry.Repo.preload(user_meal, recipe_user_meals: [recipe: [:recipe_ingredients]])

      recipes_r = Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe end)
      assert recipes_r == [recipe_0, recipe]
      # assert user_meal.recipe_user_meals.recipe == recipe_0
      assert NaiveDateTime.diff(user_meal.start_dt, ~U[2022-02-13 16:50:00Z]) == 0
      assert user_meal.title == "some title"
    end

    test "update_user_meal/2 with valid data updates the user_meal" do
      user = AccountsFixtures.user_fixture()

      recipe_0 = FoodFixtures.recipe_fixture(user, %{name: "asdffads"})
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Asdfadsf"})

      valid_attrs = %{
        start_dt: ~U[2022-02-13 16:50:00Z],
        title: "some title",
        user_id: user.id,
        recipe_user_meals: [
          %{cooking_portions: 2, consume_portions: 1, recipe_id: recipe_0.id},
          %{recipe_id: recipe.id, cooking_portions: 2, consume_portions: 1}
        ]
      }

      update_attrs = %{
        start_dt: ~U[2022-02-14 16:50:00Z],
        title: "some title2"
      }

      assert {:ok, %UserMeal{} = user_meal} = History.create_user_meal(valid_attrs)

      user_meal =
        Mehungry.Repo.preload(user_meal, recipe_user_meals: [recipe: [:recipe_ingredients]])

      recipes_r = Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe end)
      assert recipes_r == [recipe_0, recipe]

      assert {:ok, %UserMeal{} = user_meal} = History.update_user_meal(user_meal, update_attrs)
      assert NaiveDateTime.diff(user_meal.start_dt, ~U[2022-02-14 16:50:00Z]) == 0

      user_meal =
        Mehungry.Repo.preload(user_meal, recipe_user_meals: [recipe: [:recipe_ingredients]])

      [recipes_r | _rest] = Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe end)

      assert recipes_r.id == recipe_0.id
      assert user_meal.title == "some title2"
    end

    test "create_user_meal/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = History.create_user_meal(@invalid_attrs)
    end

    test "update_user_meal/2 with invalid data returns error changeset", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Asdfad23d32sf"})
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      assert {:error, %Ecto.Changeset{}} = History.update_user_meal(user_meal, @invalid_attrs)
    end

    test "delete_user_meal/1 deletes the user_meal", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Asdfad23d32sf"})
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      assert {:ok, %UserMeal{}} = History.delete_user_meal(user_meal)
      assert_raise Ecto.NoResultsError, fn -> History.get_user_meal!(user_meal.id) end
    end

    test "change_user_meal/1 returns a user_meal changeset", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Asdfad23d32sf"})
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      assert %Ecto.Changeset{} = History.change_user_meal(user_meal)
    end
  end
end
