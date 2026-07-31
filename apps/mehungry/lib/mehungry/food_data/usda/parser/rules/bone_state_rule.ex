defmodule Mehungry.FoodData.Usda.Parser.Rules.BoneStateRule do
  @moduledoc """
  Claims the first unconsumed `:bone_state` token (bone/cartilage state, e.g.
  "boneless", "bone in", "lip on") and sets `result.bone_state`. Generic — any
  vocabulary bone-state value, default `nil`.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Helpers.unconsumed(result, :bone_state) do
      [] ->
        {:ok, result}

      [bone_state | _rest] = matched ->
        result =
          result
          |> Helpers.consume(matched)
          |> Map.put(:bone_state, bone_state.value)
          |> Helpers.trace_rule(__MODULE__, %{bone_state: bone_state.value})

        {:ok, result}
    end
  end
end
