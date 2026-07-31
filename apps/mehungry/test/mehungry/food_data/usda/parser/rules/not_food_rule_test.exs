defmodule Mehungry.FoodData.Usda.Parser.Rules.NotFoodRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.NotFoodRule
  alias Mehungry.FoodData.Usda.Parser.Skipped

  test "halts with a Skipped when a not-food token is present" do
    result =
      result([token(:not_food, "alcoholic beverage")],
        raw_text: "Alcoholic beverage, daiquiri, canned"
      )

    assert {:halt,
            %Skipped{
              reason: :not_food,
              text: "Alcoholic beverage, daiquiri, canned",
              confidence: 1.0
            }} =
             NotFoodRule.apply(result)
  end

  test "passes results through when no not-food token exists" do
    result = result([token(:food, "carrot")])
    assert {:ok, ^result} = NotFoodRule.apply(result)
  end
end
