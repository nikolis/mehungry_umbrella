defmodule Mehungry.FoodData.Usda.Parser.Rules.SeedRule do
  @moduledoc "Plant-part descriptor: 'seed' becomes a processing modifier."

  use Mehungry.FoodData.Usda.Parser.Rules.DescriptorModifierRule, word: "seed"
end
