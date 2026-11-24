defmodule Mehungry.AI.Agents.MealPlanRulesTest do
  @moduledoc "Every composition rule of `MealPlanCore.Rules`, one at a time. Pure — no DB."
  use ExUnit.Case, async: true

  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.AI.Agents.MealPlanCore.Rules

  @date "2030-01-07"

  # Recipes by id: roles + total minutes.
  @meta %{
    1 => %{title: "Omelette", roles: ["breakfast", "dinner"], total_minutes: 10},
    2 => %{title: "Porridge bake", roles: ["breakfast"], total_minutes: 45},
    3 => %{title: "Moussaka", roles: ["main"], total_minutes: 105},
    4 => %{title: "Horiatiki", roles: ["salad", "side"], total_minutes: 10},
    5 => %{title: "Baklava", roles: ["dessert"], total_minutes: 90},
    6 => %{title: "Tzatziki", roles: ["meze", "side"], total_minutes: 10},
    7 => %{title: "Chicken skillet", roles: ["main"], total_minutes: 30},
    8 => %{title: "Lentil soup", roles: ["soup", "main"], total_minutes: nil},
    9 => %{title: "Mystery dish", roles: [], total_minutes: nil}
  }

  @peach 100
  @almond 200
  @cheese 300

  defp ctx(groups),
    do: %{
      recipe_meta: @meta,
      rules: MapSet.new(groups),
      fruit_ids: MapSet.new([@peach]),
      nut_ids: MapSet.new([@almond])
    }

  defp meal(slot, items), do: %{"date" => @date, "slot" => slot, "items" => items}
  defp r(id, part \\ "main"), do: %{"recipe_id" => id, "part" => part}
  defp i(id), do: %{"ingredient_id" => id, "quantity" => 1}

  defp errors(slot, items, groups \\ [:composition]),
    do: Rules.errors([meal(slot, items)], ctx(groups))

  describe "always on" do
    test "a main recipe's roles must fit its slot; unclassified fits" do
      assert [error] = errors("Dinner", [r(6)], [])
      assert error =~ ~s|"Tzatziki" (recipe_id 6) is a meze/side, not a main|
      assert errors("Dinner", [r(9)], []) == []
    end

    test "an unknown part is rejected" do
      assert [error] = errors("Lunch", [r(3), r(4, "starter")], [])
      assert error =~ ~s(part "starter")
    end
  end

  describe ":composition" do
    test "Breakfast: one breakfast recipe, optionally with ingredients" do
      assert errors("Breakfast", [r(1), i(@peach), i(@almond)]) == []
      assert [e] = errors("Breakfast", [i(@peach)])
      assert e =~ "needs one main recipe"
      assert [e] = errors("Breakfast", [r(1), r(2)])
      assert e =~ "exactly one main recipe"
      assert [e] = errors("Breakfast", [r(1), r(5, "dessert")])
      assert e =~ "remove the salad/dessert"
    end

    test "Lunch: main + optional salad + optional dessert, no ingredients" do
      assert errors("Lunch", [r(3)]) == []
      assert errors("Lunch", [r(3), r(4, "salad"), r(5, "dessert")]) == []

      assert [e] = errors("Lunch", [r(3), r(4, "salad"), r(4, "salad")])
      assert e =~ "at most one salad"

      assert [e] = errors("Lunch", [r(3), i(@cheese)])
      assert e =~ "remove the ingredient items"

      assert [e] = errors("Lunch", [r(4, "salad")])
      assert e =~ "needs one main recipe"
    end

    test "Lunch: a salad / dessert part must be that kind of dish" do
      assert [e] = errors("Lunch", [r(3), r(6, "salad")])
      assert e =~ ~s|"Tzatziki" (recipe_id 6) is not a salad|
      assert e =~ ~s(part: "salad")
      # Unclassified passes, like the slot role check.
      assert errors("Lunch", [r(3), r(9, "dessert")]) == []
    end

    test "Dinner: exactly one recipe and nothing else" do
      assert errors("Dinner", [r(7)]) == []
      assert [e] = errors("Dinner", [r(7), r(4, "salad")])
      assert e =~ "Dinner is a single recipe"
      assert [e] = errors("Dinner", [r(7), i(@peach)])
      assert e =~ "Dinner is a single recipe"
    end

    test "snacks: ingredients only, at least one" do
      assert errors("Morning Snack", [i(@cheese)]) == []
      errors = errors("Afternoon Snack", [r(5)])
      assert Enum.any?(errors, &(&1 =~ "not a recipe"))
      assert [_] = errors("Morning Snack", [])
    end
  end

  describe ":time" do
    test "Breakfast takes ≤ 15 min; unknown time fails" do
      assert errors("Breakfast", [r(1)], [:time]) == []
      assert [e] = errors("Breakfast", [r(2)], [:time])
      assert e =~ "takes 45 min"
      assert e =~ "at most 15 minutes"
      assert [e] = errors("Breakfast", [r(9)], [:time])
      assert e =~ "has no known prep/cook time"
    end

    test "Dinner takes ≤ 40 min unless it is a dinner dish" do
      assert errors("Dinner", [r(7)], [:time]) == []
      assert [e] = errors("Dinner", [r(3)], [:time])
      assert e =~ "takes 105 min"
      assert [e] = errors("Dinner", [r(8)], [:time])
      assert e =~ "no known prep/cook time"
      # A `dinner` dish passes whatever its time.
      assert errors("Dinner", [r(1)], [:time]) == []
    end

    test "Lunch has no time limit" do
      assert errors("Lunch", [r(3), r(5, "dessert")], [:time]) == []
    end
  end

  describe ":snack_kinds" do
    test "morning snack needs a seasonal fruit; afternoon snack a nut" do
      assert errors("Morning Snack", [i(@peach), i(@almond)], [:snack_kinds]) == []
      assert [e] = errors("Morning Snack", [i(@almond)], [:snack_kinds])
      assert e =~ "at least one seasonal fruit"

      assert errors("Afternoon Snack", [i(@almond)], [:snack_kinds]) == []
      assert [e] = errors("Afternoon Snack", [i(@peach)], [:snack_kinds])
      assert e =~ "at least one nut"
    end

    test "anything but fruit / nuts is rejected, at snacks and breakfast" do
      assert [e] = errors("Afternoon Snack", [i(@almond), i(@cheese)], [:snack_kinds])
      assert e =~ "ingredient_id #{@cheese} is not one of the seasonal fruits or nuts"
      assert [_] = errors("Breakfast", [r(1), i(@cheese)], [:snack_kinds])
    end

    test "no fruit in season: the morning snack falls back to nuts" do
      ctx = %{ctx([:snack_kinds]) | fruit_ids: MapSet.new()}
      assert Rules.errors([meal("Morning Snack", [i(@almond)])], ctx) == []
    end
  end

  describe ":snack_variety" do
    @kiwi 101
    @walnut 201
    @hazelnut 202

    # 7 days of snacks: `morning.(day)` / `afternoon.(day)` give each day's items.
    defp week(morning, afternoon) do
      for day <- 1..7,
          {slot, items} <- [
            {"Morning Snack", morning.(day)},
            {"Afternoon Snack", afternoon.(day)}
          ] do
        %{"date" => "2030-01-0#{day}", "slot" => slot, "items" => items}
      end
    end

    defp variety_ctx(fruit, nuts),
      do: %{
        rules: MapSet.new([:snack_variety]),
        fruit_ids: MapSet.new(fruit),
        nut_ids: MapSet.new(nuts),
        ingredient_names: %{@almond => "Almonds, unsalted"}
      }

    test "the same nut in every afternoon snack is rejected, naming the food and the dates" do
      entries = week(fn _ -> [i(@peach)] end, fn _ -> [i(@almond)] end)
      ctx = variety_ctx([@peach, @kiwi, 102, 103], [@almond, @walnut, @hazelnut])

      errors = Rules.errors(entries, ctx)

      assert Enum.any?(
               errors,
               &(&1 =~ ~s|"Almonds, unsalted" (ingredient_id #{@almond}) is in 7 snacks|)
             )

      assert Enum.any?(errors, &(&1 =~ "at most 2 snack slots"))
      # the peach fills all 7 morning snacks too
      assert Enum.any?(errors, &(&1 =~ "ingredient_id #{@peach} is in 7 snacks"))
    end

    test "a rotated week passes" do
      fruits = [@peach, @kiwi, 102, 103]
      nuts = [@almond, @walnut, @hazelnut, 203]
      entries = week(&[i(Enum.at(fruits, rem(&1, 4)))], &[i(Enum.at(nuts, rem(&1, 4)))])

      assert Rules.errors(entries, variety_ctx(fruits, nuts)) == []
    end

    test "fruit + nut in one snack is one use of each" do
      entries = [
        meal("Morning Snack", [i(@peach), i(@almond), i(@almond)]),
        %{meal("Afternoon Snack", [i(@almond)]) | "date" => "2030-01-08"}
      ]

      assert Rules.errors(entries, variety_ctx([@peach], [@almond])) == []
    end

    test "a pool too small to share the load raises the cap" do
      # one curated nut for 7 afternoon snacks: it has to repeat
      entries =
        week(&[i(Enum.at([@peach, @kiwi, 102, 103], rem(&1, 4)))], fn _ -> [i(@almond)] end)

      assert Rules.errors(entries, variety_ctx([@peach, @kiwi, 102, 103], [@almond])) == []

      # two nuts, no fruit: 14 snacks / 2 nuts = 7 each is the cap
      entries = week(fn _ -> [i(@almond)] end, fn _ -> [i(@walnut)] end)
      assert Rules.errors(entries, variety_ctx([], [@almond, @walnut])) == []
    end

    test "off unless the group is on" do
      entries = week(fn _ -> [i(@peach)] end, fn _ -> [i(@almond)] end)

      assert Rules.errors(entries, %{
               variety_ctx([@peach], [@almond, @walnut])
               | rules: MapSet.new()
             }) == []
    end
  end

  test "expand_entry/1 turns the older flat entry into a one-item meal" do
    assert %{"items" => [%{"recipe_id" => 3, "servings" => 2}]} =
             MealPlanCore.expand_entry(%{
               "date" => @date,
               "slot" => "Lunch",
               "recipe_id" => 3,
               "servings" => 2
             })

    assert %{"items" => []} = MealPlanCore.expand_entry(%{"date" => @date, "slot" => "Lunch"})
  end
end
