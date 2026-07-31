defmodule Mehungry.FoodData.Usda.Parser.Rules.PartRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.PartRule

  test "sets part from the first unconsumed :part token" do
    result = result([token(:part, "loin", segment: 1)])

    assert {:ok, applied} = PartRule.apply(result)
    assert applied.part == "loin"
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves part nil without a :part token" do
    result = result([token(:processing, "raw")])
    assert {:ok, applied} = PartRule.apply(result)
    assert applied.part == nil
  end

  test "any part value is claimed generically" do
    result = result([token(:part, "chuck", segment: 1)])
    assert {:ok, applied} = PartRule.apply(result)
    assert applied.part == "chuck"
  end
end
