defmodule Mehungry.FoodData.Usda.Parser.Rules.DismembermentRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.DismembermentRule

  test "sets dismemberment from the first unconsumed :dismemberment token" do
    result = result([token(:dismemberment, "t bone steak", segment: 2)])

    assert {:ok, applied} = DismembermentRule.apply(result)
    assert applied.dismemberment == "t bone steak"
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves dismemberment nil without a :dismemberment token" do
    result = result([token(:processing, "raw")])
    assert {:ok, applied} = DismembermentRule.apply(result)
    assert applied.dismemberment == nil
  end

  test "any dismemberment value is claimed generically" do
    result = result([token(:dismemberment, "porterhouse steak", segment: 2)])
    assert {:ok, applied} = DismembermentRule.apply(result)
    assert applied.dismemberment == "porterhouse steak"
  end
end
