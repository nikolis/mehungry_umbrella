defmodule Mehungry.FoodData.Usda.Parser.Rules.ModifierRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.ModifierRule

  test "sweeps multiple modifiers in reading order" do
    result =
      result([
        token(:food, "cucumber"),
        token(:modifier, "dill", segment: 2),
        token(:modifier, "kosher dill", segment: 2)
      ])

    assert {:ok, applied} = ModifierRule.apply(result)
    assert applied.processing_modifiers == ["dill", "kosher dill"]
  end

  test "unknown tokens in qualifier segments become modifiers" do
    result =
      result([
        token(:food, "chestnut"),
        token(:unknown, "polynesian", segment: 1)
      ])

    assert {:ok, applied} = ModifierRule.apply(result)
    assert applied.processing_modifiers == ["polynesian"]
  end

  test "unknown tokens in the head segment are not swept" do
    result = result([token(:unknown, "frobnitz", segment: 0)])
    assert {:ok, applied} = ModifierRule.apply(result)
    assert applied.processing_modifiers == []
  end

  test "duplicate values are appended once" do
    result =
      result([
        token(:modifier, "dill", segment: 1),
        token(:modifier, "dill", segment: 2)
      ])

    assert {:ok, applied} = ModifierRule.apply(result)
    assert applied.processing_modifiers == ["dill"]
  end
end
