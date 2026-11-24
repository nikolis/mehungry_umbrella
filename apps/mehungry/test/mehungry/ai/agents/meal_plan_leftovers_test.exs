defmodule Mehungry.AI.Agents.MealPlanLeftoversTest do
  @moduledoc """
  Phase 4 — a Dinner may be leftovers of that day's Lunch (`leftover_of: "Lunch"`):
  resolved to the Lunch main in `submit_plan`, exempt from the dinner role/time
  checks, and persisted as a `cooking: false` recipe row (no cooking portions)
  while the Lunch row cooks for both. The shopping list never buys for a leftover.
  No LLM.
  """
  use Mehungry.DataCase, async: true

  import Ecto.Query
  import Mehungry.AccountsFixtures
  import Mehungry.FoodFixtures, only: [recipe_fixture: 2]

  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.AI.MealPlanGenerator
  alias Mehungry.{History, Inventory, Repo}

  @day ~D[2030-01-07]
  @date "2030-01-07"

  defp acc(overrides \\ %{}) do
    Map.merge(
      %{
        start_date: @day,
        offered: MapSet.new([1, 2]),
        offered_ingredients: MapSet.new(),
        recipe_meta: %{
          1 => %{title: "Eggs", roles: ["breakfast"], calories: 300, total_minutes: 10},
          # A 105-minute main: never a fresh weeknight dinner under :time.
          2 => %{title: "Moussaka", roles: ["main"], calories: 600, total_minutes: 105}
        },
        rules: MapSet.new([:composition, :time]),
        calorie_band: nil,
        submitted: nil
      },
      overrides
    )
  end

  defp submit(entries, acc), do: MealPlanCore.submit_plan_tool(%{"entries" => entries}, acc)

  defp lunch(servings \\ 1),
    do: %{
      "date" => @date,
      "slot" => "Lunch",
      "items" => [
        %{"recipe_id" => 2, "part" => "main", "cooking_portions" => 2, "servings" => servings}
      ]
    }

  defp leftover_dinner(servings \\ 1),
    do: %{
      "date" => @date,
      "slot" => "Dinner",
      "items" => [%{"leftover_of" => "Lunch", "servings" => servings}]
    }

  describe "submit_plan" do
    test "a leftover dinner resolves to the lunch main and is exempt from the 40-min rule" do
      {result, acc} = submit([lunch(), leftover_dinner()], acc())
      assert result.success

      by_type = Map.new(acc.submitted.entries, &{&1.meal_type, &1})
      assert [%{recipe_id: 2, leftover: true, cooking_portions: 0}] = by_type["dinner"].items
    end

    test "the lunch main cooks for lunch + the leftover servings" do
      {result, acc} = submit([lunch(2), leftover_dinner(2)], acc(%{calorie_band: nil}))
      assert result.success

      # No band: servings pin to 1 each, so cooking ≥ 1 + 1 — the model's 2 stays.
      by_type = Map.new(acc.submitted.entries, &{&1.meal_type, &1})
      assert [%{cooking_portions: 2}] = by_type["lunch"].items

      band = %{min: 2300, max: 2500, aim: 2400, basis: :goal_maintain}
      {result, acc} = submit([lunch(2), leftover_dinner(2)], acc(%{calorie_band: band}))
      assert result.success

      by_type = Map.new(acc.submitted.entries, &{&1.meal_type, &1})
      [%{servings: ls, cooking_portions: cp}] = by_type["lunch"].items
      [%{servings: ds}] = by_type["dinner"].items
      assert cp >= ls + ds
      # Calories count the leftover too: 600 × (lunch + dinner servings) in band.
      assert ((ls + ds) * 600) in 2300..2500
    end

    test "the same moussaka as a fresh dinner is rejected by the time rule" do
      dinner = %{"date" => @date, "slot" => "Dinner", "items" => [%{"recipe_id" => 2}]}
      {result, _} = submit([lunch(), dinner], acc())
      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "takes 105 min"))
    end

    test "leftovers need that day's lunch in the plan" do
      {result, _} = submit([leftover_dinner()], acc())
      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "leftovers need a Lunch main recipe on #{@date}"))
    end

    test "a filled lunch cell (fill-gaps) can't feed a leftover dinner" do
      acc = acc(%{occupied_cells: MapSet.new([{@date, "Lunch"}])})
      {result, _} = submit([lunch(), leftover_dinner()], acc)
      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "leftovers need a Lunch main"))
    end

    test "leftovers are Dinner-only" do
      breakfast = %{
        "date" => @date,
        "slot" => "Breakfast",
        "items" => [%{"leftover_of" => "Lunch", "servings" => 1}]
      }

      {result, _} = submit([lunch(), breakfast], acc())
      refute result.success
      assert Enum.any?(result.errors, &(&1 =~ "leftovers are only for Dinner"))
    end
  end

  describe "persistence" do
    setup do
      user = user_fixture()
      recipe = recipe_fixture(user, %{title: "leftover stew", servings: 4})

      entries = [
        %{
          day_index: 1,
          meal_type: "lunch",
          items: [%{recipe_id: recipe.id, part: "main", cooking_portions: 3, servings: 1}]
        },
        %{
          day_index: 1,
          meal_type: "dinner",
          items: [
            %{
              recipe_id: recipe.id,
              part: "main",
              leftover: true,
              cooking_portions: 0,
              servings: 2
            }
          ]
        }
      ]

      {:ok, [_, _], 0} = MealPlanGenerator.persist_entries_to_calendar(entries, user.id, @day)
      meals = History.list_calendar_user_meals(user.id, @day, @day)
      %{user: user, recipe: recipe, meals: meals}
    end

    test "dinner is a cooking: false row; lunch cooks", %{meals: meals} do
      by_type = Map.new(meals, &{&1.meal_type, hd(&1.recipe_user_meals)})

      assert %{cooking: true, cooking_portions: 3, consume_portions: 1} = by_type["lunch"]
      assert %{cooking: false, cooking_portions: 0, consume_portions: 2} = by_type["dinner"]
    end

    test "the calendar view-model flags it and still counts what is eaten", %{meals: meals} do
      dinner =
        meals
        |> History.format_user_meals()
        |> Enum.find(&(&1.meal_type == "dinner"))

      assert [%{leftover: true, consume_portions: 2}] = dinner.recipe_user_meals
    end

    test "the shopping list buys only for the lunch that cooks", %{meals: meals} do
      ids = Enum.map(meals, & &1.id)

      meals =
        from(m in History.UserMeal, where: m.id in ^ids)
        |> Repo.all()
        |> Repo.preload(recipe_user_meals: [recipe: [recipe_ingredients: [:ingredient_portion]]])

      lunch_only = Enum.filter(meals, &(&1.meal_type == "lunch"))

      assert Inventory.aggregate_meal_ingredients(meals) ==
               Inventory.aggregate_meal_ingredients(lunch_only)
    end
  end
end
