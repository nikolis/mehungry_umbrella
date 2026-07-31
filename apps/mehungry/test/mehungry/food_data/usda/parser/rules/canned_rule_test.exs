defmodule Mehungry.FoodData.Usda.Parser.Rules.CannedRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.CannedRule

  test "sets packaging from a canned token" do
    result = result([token(:packaging, "canned", segment: 2)])

    assert {:ok, applied} = CannedRule.apply(result)
    assert applied.packaging == :canned
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves :na without a packaging token" do
    result = result([token(:food, "tomato")])
    assert {:ok, applied} = CannedRule.apply(result)
    assert applied.packaging == :na
  end
end
