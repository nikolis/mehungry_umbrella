defmodule Mehungry.FoodData.Usda.Parser.Rules.BabyRule do
  @moduledoc """
  Claims `:harvest_stage` tokens with value "baby" and sets
  `harvest_stage: :baby` (the struct default is `:mature`).
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Enum.filter(Helpers.unconsumed(result, :harvest_stage), &(&1.value == "baby")) do
      [] ->
        {:ok, result}

      matched ->
        result =
          result
          |> Helpers.consume(matched)
          |> Map.put(:harvest_stage, :baby)
          |> Helpers.trace_rule(__MODULE__, %{harvest_stage: :baby})

        {:ok, result}
    end
  end
end
