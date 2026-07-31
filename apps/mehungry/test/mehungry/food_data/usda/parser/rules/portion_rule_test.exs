defmodule Mehungry.FoodData.Usda.Parser.Rules.PortionRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.PortionRule

  test "sweeps every :portion token into the list, reading order preserved" do
    result =
      result([
        token(:portion, "meat only", segment: 1),
        token(:portion, "skinless", segment: 2)
      ])

    assert {:ok, applied} = PortionRule.apply(result)
    assert applied.portion == ["meat only", "skinless"]
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves portion empty without a :portion token" do
    result = result([token(:processing, "raw")])
    assert {:ok, applied} = PortionRule.apply(result)
    assert applied.portion == []
  end
end
