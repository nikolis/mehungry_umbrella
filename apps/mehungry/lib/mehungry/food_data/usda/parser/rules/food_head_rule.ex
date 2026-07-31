defmodule Mehungry.FoodData.Usda.Parser.Rules.FoodHeadRule do
  @moduledoc """
  Resolves `canonical_food` when no template rule already did: the first
  unconsumed `:food` token wins (USDA puts the primary food first). If the
  vocabulary knows no food at all, the normalized head phrase of segment 0 is
  kept as free text with a ×0.5 penalty (`canonical_food_id` stays nil) so
  nothing is silently dropped and the admin sees a low-confidence candidate.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Result
  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @fallback_penalty 0.5

  @impl true
  def apply(%Result{canonical_food: nil} = result) do
    case Helpers.unconsumed(result, :food) do
      [food | _rest] ->
        result =
          result
          |> Helpers.consume(food)
          |> Map.merge(%{canonical_food: food.value, canonical_food_id: food.meta[:food_id]})

        {:ok, Helpers.trace_rule(result, __MODULE__, %{food: food.value})}

      [] ->
        fallback(result)
    end
  end

  def apply(result), do: {:ok, result}

  defp fallback(%Result{segments: [[phrase | _] | _]} = result) do
    head_unknowns = Enum.filter(Helpers.unconsumed(result, :unknown), &(&1.segment == 0))

    result =
      result
      |> Helpers.consume(head_unknowns)
      |> Map.put(:canonical_food, phrase)
      |> Result.penalize(@fallback_penalty, %{
        stage: :rule,
        rule: __MODULE__,
        fallback_food: phrase
      })

    {:ok, result}
  end

  defp fallback(result), do: {:ok, result}
end
