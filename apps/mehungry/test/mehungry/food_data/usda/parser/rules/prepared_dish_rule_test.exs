defmodule Mehungry.FoodData.Usda.Parser.Rules.PreparedDishRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.PreparedDishRule
  alias Mehungry.FoodData.Usda.Parser.Skipped

  test "halts with :prepared_dish when a prepared marker is present" do
    result =
      result([token(:prepared, "commercial", segment: 1)], raw_text: "White bread, commercial")

    assert {:halt,
            %Skipped{reason: :prepared_dish, text: "White bread, commercial", confidence: 1.0}} =
             PreparedDishRule.apply(result)
  end

  test "passes through when no prepared marker is present" do
    result = result([token(:food, "carrot")])
    assert {:ok, ^result} = PreparedDishRule.apply(result)
  end
end
