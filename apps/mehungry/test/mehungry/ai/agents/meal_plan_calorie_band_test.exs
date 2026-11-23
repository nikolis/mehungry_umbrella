defmodule Mehungry.AI.Agents.MealPlanCalorieBandTest do
  @moduledoc """
  `submit_plan`'s calorie check: every planned day must total inside the run's
  calorie band, `servings` is the lever that gets it there, and a plan that still
  can't fit is accepted with honest warnings after a bounded number of rejections.

  No LLM and no catalog — the accumulator's calorie ledger is built by hand.
  """
  use Mehungry.DataCase, async: true

  alias Mehungry.AI.Agents.MealPlanCore

  @day ~D[2030-01-07]
  @date "2030-01-07"
  @band %{min: 1796, max: 2195, aim: 1995, basis: :goal_maintain}

  # Three one-serving meals: 400 + 450 + 350 = 1200 kcal — the production undershoot.
  defp acc(overrides \\ %{}) do
    Map.merge(
      %{
        start_date: @day,
        offered: MapSet.new([1, 2, 3]),
        offered_ingredients: MapSet.new(),
        recipe_meta: %{
          1 => %{title: "Eggs", roles: ["breakfast"], calories: 400},
          2 => %{title: "Stew", roles: ["main"], calories: 450},
          3 => %{title: "Soup", roles: ["soup"], calories: 350}
        },
        calorie_band: @band,
        submitted: nil
      },
      overrides
    )
  end

  defp day(servings \\ %{}) do
    for {slot, id} <- [{"Breakfast", 1}, {"Lunch", 2}, {"Dinner", 3}] do
      %{
        "date" => @date,
        "slot" => slot,
        "recipe_id" => id,
        "cooking_portions" => 2,
        "servings" => Map.get(servings, slot, 1)
      }
    end
  end

  defp submit(entries, acc), do: MealPlanCore.submit_plan_tool(%{"entries" => entries}, acc)

  test "a day under the band is rejected with the gap spelled out" do
    {result, acc} = submit(day(), acc())

    refute result.success
    assert [error] = result.errors
    assert error =~ "#{@date} totals 1200 kcal"
    assert error =~ "between 1796 and 2195"
    assert error =~ "Add about 596 kcal"
    assert acc.submitted == nil
    assert acc.calorie_rejections == 1
  end

  test "raising servings brings the day inside the band and is carried on the entries" do
    # 400 + 2×450 + 2×350 = 2000
    {result, acc} = submit(day(%{"Lunch" => 2, "Dinner" => 2}), acc())

    assert result.success
    assert acc.submitted.calorie_warnings == []

    assert %{"lunch" => 2, "dinner" => 2, "breakfast" => 1} =
             Map.new(acc.submitted.entries, &{&1.meal_type, &1.servings})
  end

  test "a day over the band is rejected too" do
    {result, _acc} = submit(day(%{"Breakfast" => 3, "Lunch" => 3, "Dinner" => 3}), acc())

    refute result.success
    assert hd(result.errors) =~ "Remove about"
  end

  test "meals already on the calendar that day count toward the total" do
    # 1200 planned + 700 staying on the calendar = 1900, inside the band.
    {result, _acc} = submit(day(), acc(%{existing_day_kcal: %{@date => 700}}))

    assert result.success
  end

  test "after two calorie-only rejections the plan is accepted with warnings" do
    {r1, acc} = submit(day(), acc())
    {r2, acc} = submit(day(), acc)
    {r3, acc} = submit(day(), acc)

    refute r1.success
    refute r2.success
    assert r3.success

    assert acc.submitted.calorie_warnings == [%{date: @date, total: 1200, min: 1796, max: 2195}]
    assert length(acc.submitted.entries) == 3
  end

  test "no band: nothing is checked and servings stay at one" do
    {result, acc} = submit(day(%{"Lunch" => 3}), acc(%{calorie_band: nil}))

    assert result.success
    assert Enum.all?(acc.submitted.entries, &(&1.servings == 1))
    assert acc.submitted.calorie_warnings == []
  end

  test "a day holding a recipe of unknown calories cannot be judged, so it passes" do
    meta = put_in(acc().recipe_meta[2].calories, nil)

    {result, _acc} = submit(day(), acc(%{recipe_meta: meta}))

    assert result.success
  end

  test "calorie_block/1 states the range, and is empty without a band" do
    block = MealPlanCore.calorie_block(@band)

    assert block =~ "between\n1796 and 2195 kcal" or block =~ "1796 and 2195 kcal"
    assert MealPlanCore.calorie_block(nil) == ""
  end
end
