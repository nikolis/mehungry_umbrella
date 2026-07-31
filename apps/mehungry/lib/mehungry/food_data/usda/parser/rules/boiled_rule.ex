defmodule Mehungry.FoodData.Usda.Parser.Rules.BoiledRule do
  @moduledoc "Claims :processing tokens for the :boiled method."

  use Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRule, method: :boiled
end
