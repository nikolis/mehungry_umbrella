defmodule Mehungry.FoodData.Usda.Parser.Rules.CannedRule do
  @moduledoc "Claims :packaging tokens for canned packaging."

  use Mehungry.FoodData.Usda.Parser.Rules.PackagingRule, type: :canned
end
