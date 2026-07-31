defmodule Mehungry.FoodData.Usda.Parser.Rules.RoastedRule do
  @moduledoc "Claims :processing tokens for the :roasted method."

  use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :roasted
end
