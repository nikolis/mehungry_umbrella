defmodule Mehungry.FoodData.Usda.Parser.Rules.FoodHeadRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.FoodHeadRule

  test "first food token wins" do
    result =
      result([
        token(:food, "carrot", meta: %{food_id: 1}),
        token(:food, "cucumber", segment: 1, meta: %{food_id: 2})
      ])

    assert {:ok, applied} = FoodHeadRule.apply(result)
    assert applied.canonical_food == "carrot"
    assert applied.canonical_food_id == 1
    assert applied.confidence == 1.0
  end

  test "does nothing when a template rule already set the food" do
    result = result([token(:food, "corn")], canonical_food: "corn")
    assert {:ok, ^result} = FoodHeadRule.apply(result)
  end

  test "unknown head falls back to free text with ×0.5 penalty and no food id" do
    result =
      result([token(:unknown, "frobnitz")],
        segments: [["frobnitz"], ["canned"]],
        confidence: 0.8
      )

    assert {:ok, applied} = FoodHeadRule.apply(result)
    assert applied.canonical_food == "frobnitz"
    assert applied.canonical_food_id == nil
    assert_in_delta applied.confidence, 0.4, 1.0e-9
    assert Enum.all?(applied.tokens, & &1.consumed)
  end
end
