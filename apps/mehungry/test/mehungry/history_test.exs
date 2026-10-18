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

    # `title` is now auto-derived from `meal_type` in the changeset, so a blank
    # title alone is no longer invalid. An out-of-vocabulary `meal_type` (plus a
    # missing user_id for the create path) is the reliable "invalid data" input.
    @invalid_attrs %{meal_datetime: nil, title: nil, meal_type: "brunch"}

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
      result = History.list_history_user_meals_for_user(user.id)
      assert Enum.any?(result, fn m -> m.id == user_meal.id end)
    end

    test "get_user_meal!/1 returns the user_meal with given id", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user)

      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]

      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})
      user_meal = History.get_user_meal!(user_meal.id)
      assert History.get_user_meal!(user_meal.id) == user_meal
    end

    test "get_user_meal!/2 returns the meal when owned by the user", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user)
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]
      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})

      assert %UserMeal{} = fetched = History.get_user_meal!(user.id, user_meal.id)
      assert fetched.id == user_meal.id
    end

    test "get_user_meal!/2 raises for a meal owned by another user", %{user: user} do
      other = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user)
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]
      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})

      assert_raise Ecto.NoResultsError, fn ->
        History.get_user_meal!(other.id, user_meal.id)
      end
    end

    test "get_user_meal_raw!/2 raises for a meal owned by another user", %{user: user} do
      other = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user)
      recipe_user_meals = [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 6}]
      user_meal = user_meal_fixture(%{user_id: user.id, recipe_user_meals: recipe_user_meals})

      assert_raise Ecto.NoResultsError, fn ->
        History.get_user_meal_raw!(other.id, user_meal.id)
      end
    end

    test "create_user_meal/1 with valid data creates a user_meal" do
      user = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(user, %{nutrients: %{}})
      recipe_0 = FoodFixtures.recipe_fixture(user, %{name: "other name", nutrients: %{}})

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
        Mehungry.Repo.preload(user_meal,
          recipe_user_meals: [recipe: [:recipe_ingredients, :recipe_hashtags]]
        )

      recipe_ids = Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe.id end)
      assert recipe_ids == [recipe_0.id, recipe.id]
      assert NaiveDateTime.diff(user_meal.start_dt, ~U[2022-02-13 16:50:00Z]) == 0
      assert user_meal.title == "some title"
    end

    test "update_user_meal/2 with valid data updates the user_meal" do
      user = AccountsFixtures.user_fixture()

      recipe_0 = FoodFixtures.recipe_fixture(user, %{name: "asdffads", nutrients: %{}})
      recipe = FoodFixtures.recipe_fixture(user, %{name: "Asdfadsf", nutrients: %{}})

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
        Mehungry.Repo.preload(user_meal,
          recipe_user_meals: [recipe: [:recipe_ingredients, :recipe_hashtags]]
        )

      recipe_ids = Enum.map(user_meal.recipe_user_meals, fn x -> x.recipe.id end)
      assert recipe_ids == [recipe_0.id, recipe.id]

      assert {:ok, %UserMeal{} = user_meal} = History.update_user_meal(user_meal, update_attrs)
      assert NaiveDateTime.diff(user_meal.start_dt, ~U[2022-02-14 16:50:00Z]) == 0

      user_meal =
        Mehungry.Repo.preload(user_meal,
          recipe_user_meals: [recipe: [:recipe_ingredients, :recipe_hashtags]]
        )

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

    test "create_user_meal/1 persists a valid meal_type", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "mt valid", nutrients: %{}})

      assert {:ok, %UserMeal{} = user_meal} =
               History.create_user_meal(%{
                 start_dt: ~U[2022-02-13 16:50:00Z],
                 title: "Breakfast bowl",
                 meal_type: "breakfast",
                 user_id: user.id,
                 recipe_user_meals: [
                   %{recipe_id: recipe.id, cooking_portions: 2, consume_portions: 1}
                 ]
               })

      assert user_meal.meal_type == "breakfast"
    end

    test "create_user_meal/1 rejects an invalid meal_type", %{user: user} do
      assert {:error, %Ecto.Changeset{} = cs} =
               History.create_user_meal(%{
                 start_dt: ~U[2022-02-13 16:50:00Z],
                 title: "x",
                 meal_type: "brunch",
                 user_id: user.id
               })

      assert "is invalid" in errors_on(cs).meal_type
    end

    test "create_user_meal/1 allows a nil meal_type (unsorted)", %{user: user} do
      assert {:ok, %UserMeal{meal_type: nil}} =
               History.create_user_meal(%{
                 start_dt: ~U[2022-02-13 16:50:00Z],
                 title: "Untyped",
                 meal_type: nil,
                 user_id: user.id
               })
    end

    test "create_user_meal/1 derives title from meal_type when title is blank", %{user: user} do
      assert {:ok, %UserMeal{title: "Lunch", meal_type: "lunch"}} =
               History.create_user_meal(%{
                 start_dt: ~U[2022-02-13 16:50:00Z],
                 title: "",
                 meal_type: "lunch",
                 user_id: user.id
               })
    end

    test "create_user_meal/1 falls back to a generic title when both blank", %{user: user} do
      assert {:ok, %UserMeal{title: "Meal", meal_type: nil}} =
               History.create_user_meal(%{
                 start_dt: ~U[2022-02-13 16:50:00Z],
                 title: "",
                 meal_type: "",
                 user_id: user.id
               })
    end
  end

  describe "calendar loading + denormalized ingredient nutrients" do
    import Mehungry.HistoryFixtures

    alias Mehungry.Food.{Ingredient, IngredientNutrient, MeasurementUnit, Nutrient}
    alias Mehungry.History.IngredientUserMeal
    alias Mehungry.Repo

    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "list_calendar_user_meals/3 returns only meals within the week range", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user)
      rums = [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]

      in_week =
        user_meal_fixture(%{
          user_id: user.id,
          start_dt: ~N[2026-03-04 12:00:00],
          recipe_user_meals: rums
        })

      _before_week =
        user_meal_fixture(%{
          user_id: user.id,
          start_dt: ~N[2026-02-24 12:00:00],
          recipe_user_meals: rums
        })

      _after_week =
        user_meal_fixture(%{
          user_id: user.id,
          start_dt: ~N[2026-03-20 12:00:00],
          recipe_user_meals: rums
        })

      result = History.list_calendar_user_meals(user.id, ~D[2026-03-02], ~D[2026-03-08])

      assert Enum.map(result, & &1.id) == [in_week.id]
    end

    test "create_user_meal stores the ingredient nutrient tree; format reads it back", %{
      user: user
    } do
      {ingredient, gram} = ingredient_with_nutrient()

      {:ok, meal} =
        History.create_user_meal(%{
          user_id: user.id,
          title: "Logged iron",
          start_dt: ~N[2026-03-04 12:00:00],
          ingredient_user_meals: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 100.0}
          ]
        })

      [ium] = Repo.all(from i in IngredientUserMeal, where: i.user_meal_id == ^meal.id)

      # The hook persisted the hierarchical tree at write time (not NotLoaded, not empty).
      assert is_map(ium.nutrients) and map_size(ium.nutrients) > 0

      # The calendar read path surfaces the stored map verbatim (no recomputation).
      [formatted] =
        History.list_calendar_user_meals(user.id, ~D[2026-03-02], ~D[2026-03-08])
        |> History.format_user_meals()

      assert [%{recipe: %{nutrients: nutrients}}] = formatted.ingredient_user_meals
      assert nutrients == ium.nutrients
    end

    test "IngredientUserMealPutNutrientsWorker backfills an emptied nutrients column", %{
      user: user
    } do
      {ingredient, gram} = ingredient_with_nutrient()

      {:ok, meal} =
        History.create_user_meal(%{
          user_id: user.id,
          title: "Legacy row",
          start_dt: ~N[2026-03-04 12:00:00],
          ingredient_user_meals: [
            %{ingredient_id: ingredient.id, measurement_unit_id: gram.id, quantity: 100.0}
          ]
        })

      [ium] = Repo.all(from i in IngredientUserMeal, where: i.user_meal_id == ^meal.id)
      stored = ium.nutrients

      # Simulate a row that predates the write-time hook.
      ium |> Ecto.Changeset.change(nutrients: %{}) |> Repo.update!()

      assert {:ok, _} =
               Mehungry.IngredientUserMealPutNutrientsWorker.perform(%Oban.Job{
                 args: %{"ingredient_user_meal_id" => ium.id}
               })

      assert Repo.get!(IngredientUserMeal, ium.id).nutrients == stored
    end

    # Persists an ingredient carrying one real `IngredientNutrient` (Iron) plus the
    # "gram" unit `gram_unit_ids/0` recognises, so a logged 100 g quantity resolves
    # to a non-empty nutrient tree through the real nutrition engine.
    defp ingredient_with_nutrient do
      gram = FoodFixtures.measurement_unit_fixture()
      mg = Repo.insert!(%MeasurementUnit{name: "mg_#{System.unique_integer([:positive])}"})

      nutrient =
        Repo.insert!(%Nutrient{
          name: "Iron, Fe",
          number: "303",
          measurement_unit_id: mg.id
        })

      ingredient = FoodFixtures.ingredient_fixture()

      Repo.insert!(%IngredientNutrient{
        ingredient_id: ingredient.id,
        nutrient_id: nutrient.id,
        amount: 18.0
      })

      {Repo.get!(Ingredient, ingredient.id), gram}
    end
  end

  describe "duplicate_user_meal/3" do
    import Mehungry.HistoryFixtures

    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "clones a recipe meal onto the target date, keeping meal_type/title", %{user: user} do
      recipe = FoodFixtures.recipe_fixture(user, %{name: "repeat dish"})

      source =
        user_meal_fixture(%{
          user_id: user.id,
          title: "Oatmeal",
          meal_type: "breakfast",
          start_dt: ~N[2026-10-12 08:00:00],
          end_dt: ~N[2026-10-12 08:30:00],
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 2, cooking_portions: 4}]
        })

      target = ~D[2026-10-18]
      assert {:ok, copy} = History.duplicate_user_meal(user.id, source.id, target)

      refute copy.id == source.id
      assert copy.title == "Oatmeal"
      assert copy.meal_type == "breakfast"
      assert NaiveDateTime.to_date(copy.start_dt) == target
      # Time-of-day is preserved.
      assert NaiveDateTime.to_time(copy.start_dt) == ~T[08:00:00]

      copy = Repo.preload(copy, :recipe_user_meals)
      assert [child] = copy.recipe_user_meals
      assert child.recipe_id == recipe.id
      assert child.consume_portions == 2
      assert child.cooking_portions == 4
    end

    test "raises for a meal that isn't the user's", %{user: user} do
      other = AccountsFixtures.user_fixture()
      recipe = FoodFixtures.recipe_fixture(other, %{name: "not mine"})

      source =
        user_meal_fixture(%{
          user_id: other.id,
          recipe_user_meals: [%{recipe_id: recipe.id, consume_portions: 1, cooking_portions: 1}]
        })

      assert_raise Ecto.NoResultsError, fn ->
        History.duplicate_user_meal(user.id, source.id, ~D[2026-10-18])
      end
    end
  end

  describe "day notes" do
    alias Mehungry.History.DayNote

    setup do
      %{user: AccountsFixtures.user_fixture()}
    end

    test "get_day_note/2 returns nil when none exists", %{user: user} do
      assert History.get_day_note(user.id, ~D[2026-10-18]) == nil
    end

    test "upsert_day_note/3 creates, then updates in place", %{user: user} do
      date = ~D[2026-10-18]

      assert {:ok, %DayNote{} = note} = History.upsert_day_note(user.id, date, "felt bloated")
      assert note.body == "felt bloated"
      assert History.get_day_note(user.id, date).body == "felt bloated"

      assert {:ok, %DayNote{} = updated} = History.upsert_day_note(user.id, date, "good energy")
      assert updated.id == note.id
      assert updated.body == "good energy"
    end

    test "upsert_day_note/3 trims the body", %{user: user} do
      assert {:ok, note} = History.upsert_day_note(user.id, ~D[2026-10-18], "  spaced  ")
      assert note.body == "spaced"
    end

    test "upsert_day_note/3 with a blank body deletes an existing note (and is a no-op otherwise)",
         %{user: user} do
      date = ~D[2026-10-18]

      # No-op when none exists.
      assert {:ok, nil} = History.upsert_day_note(user.id, date, "   ")
      assert {:ok, nil} = History.upsert_day_note(user.id, date, nil)

      {:ok, _} = History.upsert_day_note(user.id, date, "something")
      assert {:ok, nil} = History.upsert_day_note(user.id, date, "")
      assert History.get_day_note(user.id, date) == nil
    end

    test "list_day_notes/3 returns a date=>body map scoped to the week and user", %{user: user} do
      other = AccountsFixtures.user_fixture()

      {:ok, _} = History.upsert_day_note(user.id, ~D[2026-10-12], "monday")
      {:ok, _} = History.upsert_day_note(user.id, ~D[2026-10-15], "thursday")
      # Outside the week window.
      {:ok, _} = History.upsert_day_note(user.id, ~D[2026-10-20], "next week")
      # Another user, same week.
      {:ok, _} = History.upsert_day_note(other.id, ~D[2026-10-13], "not mine")

      notes = History.list_day_notes(user.id, ~D[2026-10-12], ~D[2026-10-18])

      assert notes == %{~D[2026-10-12] => "monday", ~D[2026-10-15] => "thursday"}
    end

    test "one note per user per day (unique)", %{user: user} do
      date = ~D[2026-10-18]
      {:ok, _} = History.upsert_day_note(user.id, date, "first")

      assert {:error, changeset} =
               %DayNote{}
               |> DayNote.changeset(%{user_id: user.id, date: date, body: "dup"})
               |> Repo.insert()

      assert %{user_id: _} = errors_on(changeset)
    end
  end
end
