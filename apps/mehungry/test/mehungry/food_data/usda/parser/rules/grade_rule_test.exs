defmodule Mehungry.FoodData.Usda.Parser.Rules.GradeRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.GradeRule

  test "sets grade from the first unconsumed :grade token" do
    result = result([token(:grade, "choice", segment: 1)])

    assert {:ok, applied} = GradeRule.apply(result)
    assert applied.grade == "choice"
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves grade nil without a :grade token" do
    result = result([token(:processing, "raw")])
    assert {:ok, applied} = GradeRule.apply(result)
    assert applied.grade == nil
  end
end
