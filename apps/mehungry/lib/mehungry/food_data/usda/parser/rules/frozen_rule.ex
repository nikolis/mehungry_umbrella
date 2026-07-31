defmodule Mehungry.FoodData.Usda.Parser.Rules.FrozenRule do
  @moduledoc "Claims :processing tokens for the :frozen method."

  use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :frozen
end
