defmodule Mehungry.FoodData.Usda.Parser.Rules.PreparedDishRule do
  @moduledoc """
  Halts the engine with `%Skipped{reason: :prepared_dish}` when the classifier
  found a prepared-dish marker ("commercial", "commercially baked", "homemade",
  "fast food", "restaurant prepared", ...). Runs up front, alongside
  `NotFoodRule`: these are composite FNDDS-style dishes outside the parser's
  "Primary, qualifier" Foundation-food grammar.

  A **marker heuristic** — unmarked dish names still fall through to the
  low-confidence free-text head fallback and surface in admin review.
  Confidence stays 1.0 — the skip is an exact vocabulary hit.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.{Result, Skipped}
  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(%Result{} = result) do
    case Helpers.unconsumed(result, :prepared) do
      [] ->
        {:ok, result}

      [token | _rest] ->
        traced = Helpers.trace_rule(result, __MODULE__, %{skipped: token.value})

        {:halt,
         %Skipped{
           reason: :prepared_dish,
           text: result.raw_text,
           confidence: 1.0,
           trace: traced.trace
         }}
    end
  end
end
