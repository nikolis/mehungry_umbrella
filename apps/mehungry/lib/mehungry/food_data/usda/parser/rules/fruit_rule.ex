defmodule Mehungry.FoodData.Usda.Parser.Rules.FruitRule do
  @moduledoc "Plant-part descriptor: 'fruit' becomes a processing modifier."

  use Mehungry.FoodData.Usda.Parser.Rules.DescriptorModifierRule, word: "fruit"
end
