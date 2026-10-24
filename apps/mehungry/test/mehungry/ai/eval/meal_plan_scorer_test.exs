defmodule Mehungry.AI.Eval.MealPlanScorerTest do
  @moduledoc """
  Deterministic unit tests for the Layer-1 meal-plan scorer. No LLM, no DB — we
  feed hand-built plans and assert the scorecard. This guards the eval's own
  measuring stick so a green :ai_eval run can be trusted.
  """
  use ExUnit.Case, async: true

  alias Mehungry.AI.Eval.MealPlanScorer

  @main_slots ~w(breakfast lunch dinner)
  @snack_slots ~w(morning_snack afternoon_snack)
  @order ~w(breakfast morning_snack lunch afternoon_snack dinner)

  # A structurally ideal 35-entry plan: all slots filled once, every recipe
  # distinct (so ≤2× trivially), snacks are ingredients.
  defp perfect_plan do
    for day <- 1..7, {mt, idx} <- Enum.with_index(@order) do
      base = %{day_index: day, meal_type: mt}

      if mt in @snack_slots do
        Map.merge(base, %{ingredient_id: 1000 + day * 10 + idx, quantity: 1.0, recipe_id: nil})
      else
        Map.merge(base, %{recipe_id: day * 10 + idx, cooking_portions: 2, ingredient_id: nil})
      end
    end
  end

  defp check(scorecard, key), do: Enum.find(scorecard.checks, &(&1.key == key))

  describe "structural checks on an ideal plan" do
    test "a perfect plan passes with full structural scores" do
      card = MealPlanScorer.score(perfect_plan())

      assert check(card, :completeness).status == :pass
      assert check(card, :all_slots_filled).status == :pass
      assert check(card, :variety).status == :pass
      assert check(card, :snacks_are_ingredients).status == :pass
      assert card.passed?
    end

    test "an empty plan fails completeness outright" do
      card = MealPlanScorer.score([])
      assert check(card, :completeness).status == :fail
      assert check(card, :completeness).score == 0.0
      refute card.passed?
    end

    test "a short plan warns on completeness and missing slots" do
      card = MealPlanScorer.score(Enum.take(perfect_plan(), 20))
      assert check(card, :completeness).status == :warn
      assert check(card, :all_slots_filled).status == :warn
      assert check(card, :all_slots_filled).detail =~ "missing"
    end
  end

  describe "variety check" do
    test "flags a recipe used more than twice" do
      plan =
        perfect_plan()
        |> Enum.map(fn e ->
          if e.meal_type in @main_slots, do: %{e | recipe_id: 777}, else: e
        end)

      card = MealPlanScorer.score(plan)
      v = check(card, :variety)
      assert v.status == :warn
      assert v.detail =~ "more than 2"
      assert v.score < 1.0
    end

    test "skips when there are no recipe entries" do
      ingredient_only =
        Enum.map(perfect_plan(), fn e ->
          %{day_index: e.day_index, meal_type: e.meal_type, ingredient_id: 1, quantity: 1.0}
        end)

      assert check(MealPlanScorer.score(ingredient_only), :variety).status == :skip
    end
  end

  describe "snacks-are-ingredients check" do
    test "warns when a snack slot is a recipe" do
      plan =
        perfect_plan()
        |> Enum.map(fn e ->
          if e.meal_type == "morning_snack",
            do: %{day_index: e.day_index, meal_type: e.meal_type, recipe_id: 55, cooking_portions: 1},
            else: e
        end)

      s = check(MealPlanScorer.score(plan), :snacks_are_ingredients)
      assert s.status == :warn
      assert s.score < 1.0
    end
  end

  describe "avoid-foods check (end-to-end, hard rule)" do
    test "skips when no avoid list is configured" do
      assert check(MealPlanScorer.score(perfect_plan()), :avoid_foods).status == :skip
    end

    test "passes when no entry name contains an avoid term" do
      ctx = %{avoid_terms: ["garlic"], recipe_names: %{10 => "Oatmeal Breakfast"}}
      card = MealPlanScorer.score([%{day_index: 1, meal_type: "breakfast", recipe_id: 10}], ctx)
      assert check(card, :avoid_foods).status == :pass
    end

    test "fails when a dish name contains an avoided food" do
      ctx = %{
        avoid_terms: ["garlic"],
        recipe_names: %{11 => "Slow Roasted Garlic Chicken Dinner"}
      }

      card = MealPlanScorer.score([%{day_index: 1, meal_type: "dinner", recipe_id: 11}], ctx)
      a = check(card, :avoid_foods)
      assert a.status == :fail
      assert a.detail =~ "garlic"
      refute card.passed?
    end
  end

  describe "preferred-foods check" do
    test "passes when every preferred term appears" do
      ctx = %{
        preferred_terms: ["salmon", "yogurt"],
        recipe_names: %{1 => "Baked Salmon Dinner"},
        ingredient_names: %{2 => "Greek Yogurt"}
      }

      entries = [
        %{day_index: 1, meal_type: "dinner", recipe_id: 1},
        %{day_index: 1, meal_type: "morning_snack", ingredient_id: 2}
      ]

      assert check(MealPlanScorer.score(entries, ctx), :preferred_foods).status == :pass
    end

    test "warns when a preferred term is absent" do
      ctx = %{preferred_terms: ["salmon", "tofu"], recipe_names: %{1 => "Baked Salmon Dinner"}}
      card = MealPlanScorer.score([%{day_index: 1, meal_type: "dinner", recipe_id: 1}], ctx)
      assert check(card, :preferred_foods).status == :warn
    end
  end

  describe "calorie-fit check" do
    test "skips without a target" do
      assert check(MealPlanScorer.score(perfect_plan()), :calorie_fit).status == :skip
    end

    test "skips when all day energies are zero (no nutrition data)" do
      macros = Map.new(1..7, fn d -> {d, %{energy_kcal: 0}} end)
      ctx = %{daily_calorie_target: 2000, day_macros: macros}
      assert check(MealPlanScorer.score(perfect_plan(), ctx), :calorie_fit).status == :skip
    end

    test "passes when every day is within tolerance" do
      macros = Map.new(1..7, fn d -> {d, %{energy_kcal: 2050}} end)
      ctx = %{daily_calorie_target: 2000, day_macros: macros}
      assert check(MealPlanScorer.score(perfect_plan(), ctx), :calorie_fit).status == :pass
    end

    test "warns when some days fall outside tolerance" do
      macros =
        Map.new(1..7, fn d -> {d, %{energy_kcal: if(d <= 2, do: 3500, else: 2000)}} end)

      ctx = %{daily_calorie_target: 2000, day_macros: macros}
      c = check(MealPlanScorer.score(perfect_plan(), ctx), :calorie_fit)
      assert c.status == :warn
      assert c.score < 1.0
    end
  end

  test "format/1 renders a readable scorecard" do
    out = MealPlanScorer.format(MealPlanScorer.score(perfect_plan()))
    assert out =~ "Meal-plan scorecard"
    assert out =~ "completeness"
  end
end
