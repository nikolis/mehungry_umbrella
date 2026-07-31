defmodule Mehungry.FoodData.Usda.Parser.Rules.NotFoodRule do
  @moduledoc """
  Halts the engine with a `%Skipped{reason: :not_food}` when the classifier
  found a not-food marker ("alcoholic beverage", ...). Runs first so nothing
  else is inferred for skipped descriptions; confidence stays 1.0 — the skip
  is an exact vocabulary hit, not a guess.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers
  alias Mehungry.FoodData.Usda.Parser.{Result, Skipped}

  @impl true
  def apply(%Result{} = result) do
    case Helpers.unconsumed(result, :not_food) do
      [] ->
        {:ok, result}

      [token | _rest] ->
        traced = Helpers.trace_rule(result, __MODULE__, %{skipped: token.value})

        {:halt,
         %Skipped{reason: :not_food, text: result.raw_text, confidence: 1.0, trace: traced.trace}}
    end
  end
end
