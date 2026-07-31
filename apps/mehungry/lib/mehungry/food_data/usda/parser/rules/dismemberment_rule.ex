defmodule Mehungry.FoodData.Usda.Parser.Rules.DismembermentRule do
  @moduledoc """
  Claims the first unconsumed `:dismemberment` token (the specific retail cut
  a `part` was butchered into, e.g. "t bone steak", "drumstick") and sets
  `result.dismemberment`. Generic like `PartRule` — one module claims any
  dismemberment, not one per value. Default is `nil`: most foods aren't cuts
  of meat.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Helpers.unconsumed(result, :dismemberment) do
      [] ->
        {:ok, result}

      [dismemberment | _rest] = matched ->
        result =
          result
          |> Helpers.consume(matched)
          |> Map.put(:dismemberment, dismemberment.value)
          |> Helpers.trace_rule(__MODULE__, %{dismemberment: dismemberment.value})

        {:ok, result}
    end
  end
end
