defmodule Mehungry.FoodData.Usda.Parser.Rules.LeafRule do
  @moduledoc "Plant-part descriptor: 'leaf' becomes a processing modifier."

  use Mehungry.FoodData.Usda.Parser.Rules.DescriptorModifierRule, word: "leaf"
end
