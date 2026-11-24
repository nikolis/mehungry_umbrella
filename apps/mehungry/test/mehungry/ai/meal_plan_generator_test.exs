defmodule Mehungry.AI.MealPlanGeneratorTest do
  @moduledoc """
  The generation → persistence seam: the existing-meals modes every AI planner
  shares (`:fill_gaps` / `:replace_week`), the `:from` guard that keeps a week's
  earlier days untouched, and the absence of any fallback when the agent fails.
  No LLM.
  """
  # async: false — the AI client stub is set through global application env.
  use Mehungry.DataCase, async: false

  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.{MealPlanGenerator, ScriptedClient}
  alias Mehungry.History

  @monday ~D[2030-01-07]

  setup do
    user = user_fixture()
    recipe = recipe_fixture(user, %{title: "generator test recipe"})
    %{user: user, recipe: recipe}
  end

  describe "parse_mode/1" do
    test "accepts both modes and defaults anything else to the non-destructive one" do
      assert MealPlanGenerator.parse_mode("replace_week") == :replace_week
      assert MealPlanGenerator.parse_mode(:replace_week) == :replace_week
      assert MealPlanGenerator.parse_mode("fill_gaps") == :fill_gaps
      assert MealPlanGenerator.parse_mode(nil) == :fill_gaps
      assert MealPlanGenerator.parse_mode("drop everything") == :fill_gaps
    end
  end

  describe "persist_entries_to_calendar/5 — servings" do
    test "an entry's servings become the servings eaten; cooked portions never fall below them",
         %{user: user, recipe: recipe} do
      entries = [
        Map.put(entry(1, "lunch", recipe.id), :servings, 3),
        entry(1, "dinner", recipe.id)
      ]

      assert {:ok, [_, _], 0} =
               MealPlanGenerator.persist_entries_to_calendar(entries, user.id, @monday)

      by_slot =
        user.id
        |> week_meals()
        |> Map.new(fn meal -> {meal.meal_type, hd(meal.recipe_user_meals)} end)

      assert by_slot["lunch"].consume_portions == 3
      assert by_slot["lunch"].cooking_portions == 3
      # No servings on the entry (older callers, blueprint plans) → one serving.
      assert by_slot["dinner"].consume_portions == 1
      assert by_slot["dinner"].cooking_portions == 2
    end
  end

  describe "persist_entries_to_calendar/5 — composite meals" do
    test "one entry's items land on one calendar meal", %{user: user, recipe: main} do
      salad = recipe_fixture(user, %{title: "generator salad"})
      dessert = recipe_fixture(user, %{title: "generator dessert"})
      ingredient = Mehungry.FoodFixtures.ingredient_fixture(%{name: "zzgen peach"})
      gram = Mehungry.FoodFixtures.measurement_unit_fixture()

      lunch = %{
        day_index: 1,
        meal_type: "lunch",
        items: [
          %{recipe_id: main.id, part: "main", cooking_portions: 2, servings: 2},
          %{recipe_id: salad.id, part: "salad", cooking_portions: 2, servings: 1},
          %{recipe_id: dessert.id, part: "dessert", cooking_portions: 4, servings: 1}
        ]
      }

      snack = %{
        day_index: 1,
        meal_type: "morning_snack",
        items: [
          %{
            ingredient_id: ingredient.id,
            quantity: 1.0,
            measurement_unit_id: gram.id,
            ingredient_portion_id: nil
          }
        ]
      }

      assert {:ok, [_, _], 0} =
               MealPlanGenerator.persist_entries_to_calendar([lunch, snack], user.id, @monday)

      by_slot = user.id |> week_meals() |> Map.new(&{&1.meal_type, &1})

      lunch_rows = Map.new(by_slot["lunch"].recipe_user_meals, &{&1.recipe_id, &1})
      assert map_size(lunch_rows) == 3
      assert lunch_rows[main.id].consume_portions == 2
      assert lunch_rows[dessert.id].cooking_portions == 4
      assert [%{ingredient_id: id}] = by_slot["morning_snack"].ingredient_user_meals
      assert id == ingredient.id
    end
  end

  describe "persist_entries_to_calendar/5 — :fill_gaps" do
    test "keeps an existing meal and writes only the empty cells", %{user: user, recipe: recipe} do
      existing = log_meal(user.id, @monday, "breakfast")

      entries = [entry(1, "breakfast", recipe.id), entry(1, "lunch", recipe.id)]

      assert {:ok, [created], 0} =
               MealPlanGenerator.persist_entries_to_calendar(
                 entries,
                 user.id,
                 @monday,
                 :fill_gaps
               )

      assert created.meal_type == "lunch"

      ids = user.id |> week_meals() |> Enum.map(& &1.id)
      assert existing.id in ids
      assert length(ids) == 2
    end

    test "a meal with no slot (unsorted) does not block a cell", %{user: user, recipe: recipe} do
      log_meal(user.id, @monday, nil)

      assert {:ok, [_created], 0} =
               MealPlanGenerator.persist_entries_to_calendar(
                 [entry(1, "breakfast", recipe.id)],
                 user.id,
                 @monday
               )
    end
  end

  describe "persist_entries_to_calendar/5 — :replace_week" do
    test "deletes every meal in the week, then writes the plan", %{user: user, recipe: recipe} do
      old = log_meal(user.id, @monday, "breakfast")
      old_unsorted = log_meal(user.id, Date.add(@monday, 3), nil)
      outside = log_meal(user.id, Date.add(@monday, 7), "dinner")

      assert {:ok, [created], 0} =
               MealPlanGenerator.persist_entries_to_calendar(
                 [entry(2, "dinner", recipe.id)],
                 user.id,
                 @monday,
                 :replace_week
               )

      ids = user.id |> week_meals() |> Enum.map(& &1.id)
      assert ids == [created.id]
      refute old.id in ids
      refute old_unsorted.id in ids
      # A meal outside the 7-day span is never touched.
      assert History.get_user_meal!(outside.id)
    end

    test "an empty plan deletes nothing", %{user: user} do
      old = log_meal(user.id, @monday, "breakfast")

      assert {:ok, [], 0} =
               MealPlanGenerator.persist_entries_to_calendar([], user.id, @monday, :replace_week)

      assert [%{id: id}] = week_meals(user.id)
      assert id == old.id
    end

    test "is all-or-nothing: a failed insert leaves the week exactly as it was", %{
      user: user,
      recipe: recipe
    } do
      old = log_meal(user.id, @monday, "breakfast")
      hand_entered = log_meal(user.id, Date.add(@monday, 3), nil)

      # The second entry cannot be saved (no such recipe).
      entries = [entry(1, "lunch", recipe.id), entry(2, "lunch", -1)]

      result =
        try do
          MealPlanGenerator.persist_entries_to_calendar(entries, user.id, @monday, :replace_week)
        rescue
          error -> {:raised, error}
        end

      refute match?({:ok, _, _}, result)

      # Nothing was deleted and the first entry was not kept either.
      ids = user.id |> week_meals() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([old.id, hand_entered.id])
    end

    test ":from leaves the week's earlier days untouched", %{user: user, recipe: recipe} do
      wednesday = Date.add(@monday, 2)
      past = log_meal(user.id, @monday, "breakfast")
      upcoming = log_meal(user.id, wednesday, "breakfast")

      entries = [entry(1, "lunch", recipe.id), entry(3, "lunch", recipe.id)]

      assert {:ok, [created], 0} =
               MealPlanGenerator.persist_entries_to_calendar(
                 entries,
                 user.id,
                 @monday,
                 :replace_week,
                 from: wednesday
               )

      ids = user.id |> week_meals() |> Enum.map(& &1.id)
      # Monday (before `from`): nothing deleted, nothing written.
      assert past.id in ids
      # Wednesday onward: replaced.
      refute upcoming.id in ids
      assert created.id in ids
      assert length(ids) == 2
    end
  end

  describe "existing_meal_count/3" do
    test "counts the week, optionally only from a later day", %{user: user} do
      log_meal(user.id, @monday, "breakfast")
      log_meal(user.id, Date.add(@monday, 4), "lunch")
      log_meal(user.id, Date.add(@monday, 9), "lunch")

      assert MealPlanGenerator.existing_meal_count(user.id, @monday) == 2
      assert MealPlanGenerator.existing_meal_count(user.id, @monday, Date.add(@monday, 2)) == 1
    end
  end

  describe "plan_from/2" do
    test "today, while the plan week is running" do
      assert MealPlanGenerator.plan_from(@monday, Date.add(@monday, 1)) == Date.add(@monday, 1)
      assert MealPlanGenerator.plan_from(@monday, Date.add(@monday, 6)) == Date.add(@monday, 6)
    end

    test "nil — the whole week — when it starts today or later, or is already over" do
      assert MealPlanGenerator.plan_from(@monday, @monday) == nil
      assert MealPlanGenerator.plan_from(@monday, Date.add(@monday, -3)) == nil
      assert MealPlanGenerator.plan_from(@monday, Date.add(@monday, 7)) == nil
    end
  end

  describe "generate_entries/4" do
    test "an agent failure is returned as an error — there is no fallback pipeline", %{user: user} do
      ScriptedClient.script([{:error, "API returned status 500"}])
      on_exit(&ScriptedClient.reset/0)

      assert {:error, "API returned status 500"} =
               MealPlanGenerator.generate_entries("vegan week", @monday, user.id, nil)

      # Exactly one request was made: nothing retried the plan through another path.
      assert {:error, "script exhausted"} = ScriptedClient.request(%{})
    end

    test "a run that never submits a plan is retried once, then is an error", %{user: user} do
      ScriptedClient.script([
        ScriptedClient.end_turn("I could not find anything."),
        ScriptedClient.end_turn("Still nothing.")
      ])

      on_exit(&ScriptedClient.reset/0)

      assert {:error, :no_plan_submitted} =
               MealPlanGenerator.generate_entries("anything", @monday, user.id, nil)

      # Exactly two passes: the original and one firmer retry.
      assert {:error, "script exhausted"} = ScriptedClient.request(%{})
    end
  end

  # ── helpers ─────────────────────────────────────────────────────────────────────

  defp entry(day_index, meal_type, recipe_id) do
    %{
      day_index: day_index,
      meal_type: meal_type,
      recipe_id: recipe_id,
      cooking_portions: 2,
      ingredient_id: nil,
      quantity: nil,
      measurement_unit_id: nil,
      ingredient_portion_id: nil
    }
  end

  defp log_meal(user_id, %Date{} = date, meal_type) do
    {:ok, start_dt} = NaiveDateTime.new(date, ~T[09:00:00])

    {:ok, meal} =
      History.create_user_meal(%{
        user_id: user_id,
        meal_type: meal_type,
        title: History.MealType.label(meal_type),
        start_dt: start_dt,
        end_dt: NaiveDateTime.add(start_dt, 3600)
      })

    meal
  end

  defp week_meals(user_id),
    do: History.list_calendar_user_meals(user_id, @monday, Date.add(@monday, 6))
end
