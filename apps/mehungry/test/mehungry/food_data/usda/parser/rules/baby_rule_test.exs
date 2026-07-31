defmodule Mehungry.FoodData.Usda.Parser.Rules.BabyRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.BabyRule

  test "sets harvest_stage to :baby" do
    result = result([token(:harvest_stage, "baby", segment: 1)])

    assert {:ok, applied} = BabyRule.apply(result)
    assert applied.harvest_stage == :baby
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves the default :mature without a baby token" do
    result = result([token(:harvest_stage, "mature", segment: 1)])
    assert {:ok, applied} = BabyRule.apply(result)
    assert applied.harvest_stage == :mature
  end
end
