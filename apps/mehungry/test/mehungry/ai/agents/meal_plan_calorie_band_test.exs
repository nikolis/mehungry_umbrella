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

  # A day no amounts can rescue: three 100-kcal dishes top out at 2+3+3 servings
  # = 800 kcal, far under the band — it needs different dishes.
  defp thin_acc do
    meta = Map.new(acc().recipe_meta, fn {id, m} -> {id, %{m | calories: 100}} end)
    acc(%{recipe_meta: meta})
  end

  defp total(entries, acc) do
    Enum.sum(for e <- entries, do: acc.recipe_meta[e.recipe_id].calories * e.servings)
  end

  describe "deterministic balancing (the code sets the amounts)" do
    test "an under-band day is brought inside the band by raising servings" do
      # The model submits 1,200 kcal of one-serving meals — the production undershoot.
      {result, acc} = submit(day(), acc())

      assert result.success
      assert acc.submitted.calorie_warnings == []
      assert total(acc.submitted.entries, acc) in 1796..2195

      # Smallest intervention that lands nearest the aim: lunch and dinner at two
      # servings (2,000 kcal) rather than one meal tripled.
      assert %{"breakfast" => 1, "lunch" => 2, "dinner" => 2} =
               Map.new(acc.submitted.entries, &{&1.meal_type, &1.servings})
    end

    test "an over-band day is brought down, and a day already inside is left alone" do
      {over, acc_over} = submit(day(%{"Breakfast" => 2, "Lunch" => 3, "Dinner" => 3}), acc())
      assert over.success
      assert total(acc_over.submitted.entries, acc_over) in 1796..2195

      # 400 + 2×450 + 2×350 = 2,000: untouched.
      {inside, acc_in} = submit(day(%{"Lunch" => 2, "Dinner" => 2}), acc())
      assert inside.success

      assert %{"breakfast" => 1, "lunch" => 2, "dinner" => 2} =
               Map.new(acc_in.submitted.entries, &{&1.meal_type, &1.servings})
    end

    test "dinner is never left heavier than lunch when a lighter-dinner option fits" do
      # Lunch 300, dinner 500: raising only dinner would fit but invert the day.
      meta =
        acc().recipe_meta
        |> put_in([2, :calories], 300)
        |> put_in([3, :calories], 500)

      {result, acc} = submit(day(), acc(%{recipe_meta: meta}))

      assert result.success
      by_slot = Map.new(acc.submitted.entries, &{&1.meal_type, &1})
      assert by_slot["lunch"].servings * 300 >= by_slot["dinner"].servings * 500
    end

    test "the production week: every day lands in 1,796–2,195 with the same dishes" do
      # Per-serving kcal and the model's servings, as drafted for the client.
      days = [
        {[500, 1, 337, 3, 256, 1], 426},
        {[500, 1, 743, 2, 256, 1], 201},
        {[244, 1, 853, 1, 215, 2], 255},
        {[500, 1, 671, 1, 303, 1], 282},
        {[244, 1, 373, 2, 256, 1], 348},
        {[244, 1, 743, 2, 337, 1], 361}
      ]

      for {[b, bs, l, ls, d, ds], snacks_kcal} <- days do
        meta = %{
          1 => %{title: "B", roles: ["breakfast"], calories: b},
          2 => %{title: "L", roles: ["main"], calories: l},
          3 => %{title: "D", roles: ["soup"], calories: d}
        }

        # Snacks ride along as calories already on the day.
        acc = acc(%{recipe_meta: meta, existing_day_kcal: %{@date => snacks_kcal}})

        {result, acc} =
          submit(day(%{"Breakfast" => bs, "Lunch" => ls, "Dinner" => ds}), acc)

        assert result.success
        assert (total(acc.submitted.entries, acc) + snacks_kcal) in 1796..2195
      end
    end
  end

  test "a day no amounts can fix is rejected with the gap spelled out" do
    {result, acc} = submit(day(), thin_acc())

    refute result.success
    assert [error] = result.errors
    # Balanced as far as amounts go (2 + 3 + 3 servings of 100 kcal) and still short.
    assert error =~ "#{@date} totals 800 kcal"
    assert error =~ "between 1796 and 2195"
    assert error =~ "Add about 996 kcal"
    assert acc.submitted == nil
    assert acc.calorie_rejections == 1
  end

  test "a day that cannot come down far enough is rejected too" do
    meta = Map.new(acc().recipe_meta, fn {id, m} -> {id, %{m | calories: 1000}} end)

    {result, _acc} = submit(day(), acc(%{recipe_meta: meta}))

    refute result.success
    assert hd(result.errors) =~ "Remove about"
  end

  test "meals already on the calendar that day count toward the total" do
    # 1,200 planned + 700 staying on the calendar = 1,900: inside, nothing changes.
    {result, acc} = submit(day(), acc(%{existing_day_kcal: %{@date => 700}}))

    assert result.success
    assert Enum.all?(acc.submitted.entries, &(&1.servings == 1))
  end

  test "after two calorie-only rejections the plan is accepted with warnings" do
    {r1, acc} = submit(day(), thin_acc())
    {r2, acc} = submit(day(), acc)
    {r3, acc} = submit(day(), acc)

    refute r1.success
    refute r2.success
    assert r3.success

    assert acc.submitted.calorie_warnings == [%{date: @date, total: 800, min: 1796, max: 2195}]
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
