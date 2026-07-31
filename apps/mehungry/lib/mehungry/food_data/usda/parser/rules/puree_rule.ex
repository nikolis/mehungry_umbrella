defmodule Mehungry.FoodData.Usda.Parser.Rules.PureeRule do
  @moduledoc "Claims :processing tokens for the :puree method."

  use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :puree
end
