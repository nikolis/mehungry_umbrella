defmodule Mehungry.FoodData.Usda.Parser.Rules.FatRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.FatRule

  test "captures a percentage fat segment and consumes its unknown tokens" do
    result =
      result(
        [
          token(:food, "milk", segment: 0),
          token(:unknown, "3.25%", segment: 1),
          token(:unknown, "milkfat", segment: 1)
        ],
        segments: [["milk"], ["3.25% milkfat"]]
      )

    assert {:ok, applied} = FatRule.apply(result)
    assert applied.fat == "3.25% milkfat"
    # unknown tokens consumed; the food is untouched
    assert Enum.filter(applied.tokens, & &1.consumed) |> Enum.map(& &1.value) == [
             "3.25%",
             "milkfat"
           ]
  end

  test "captures a lean/fat ratio segment" do
    result =
      result(
        [token(:food, "beef", segment: 0), token(:unknown, "85%", segment: 1)],
        segments: [["beef"], ["85% lean 15% fat"]]
      )

    assert {:ok, applied} = FatRule.apply(result)
    assert applied.fat == "85% lean 15% fat"
  end

  test "captures a trim-level segment" do
    result =
      result(
        [token(:food, "beef", segment: 0), token(:unknown, "trimmed", segment: 1)],
        segments: [["beef"], ["trimmed to 1/8 fat"]]
      )

    assert {:ok, applied} = FatRule.apply(result)
    assert applied.fat == "trimmed to 1/8 fat"
  end

  test "leaves fat nil when no segment matches" do
    result = result([token(:food, "carrot", segment: 0)], segments: [["carrot"], ["raw"]])
    assert {:ok, applied} = FatRule.apply(result)
    assert applied.fat == nil
  end
end
