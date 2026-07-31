defmodule Mehungry.FoodData.Usda.Parser.Rules.PartRule do
  @moduledoc """
  Claims the first unconsumed `:part` token (a USDA primal/body-part
  descriptor, e.g. "loin", "chuck", "breast") and sets `result.part`.
  Unlike `harvest_stage`, the vocabulary here can grow to cover many parts, so
  this rule is generic — one module claims any part, not one per value.
  Default is `nil`: most foods have no part.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Helpers.unconsumed(result, :part) do
      [] ->
        {:ok, result}

      [part | _rest] = matched ->
        result =
          result
          |> Helpers.consume(matched)
          |> Map.put(:part, part.value)
          |> Helpers.trace_rule(__MODULE__, %{part: part.value})

        {:ok, result}
    end
  end
end
