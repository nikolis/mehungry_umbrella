defmodule Mehungry.FoodData.Usda.Parser.Rules.PickleRule do
  @moduledoc """
  Head template `"Pickles, <ingredient>, <modifier>"`: "Pickles" is not a
  food — it means processing `:pickled` of an (explicit or implied) food.
  The vocabulary alias "pickle" carries `implied_food: "cucumber"`, used with
  a ×0.9 confidence penalty when no explicit food token is present
  (bare "Pickles").
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Result
  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @implied_food_penalty 0.9

  @impl true
  def apply(%Result{} = result) do
    case head_pickle_token(result) do
      nil ->
        {:ok, result}

      token ->
        result =
          result
          |> Helpers.consume(token)
          |> Map.update!(:processing, &Helpers.append_unique(&1, :pickled))
          |> assign_food(token)

        {:ok,
         Helpers.trace_rule(result, __MODULE__, %{
           processing: :pickled,
           food: result.canonical_food
         })}
    end
  end

  defp head_pickle_token(result) do
    result
    |> Helpers.unconsumed(:processing)
    |> Enum.find(&(&1.value == "pickled" and &1.segment == 0 and &1.meta[:head] == true))
  end

  defp assign_food(result, head_token) do
    case Helpers.unconsumed(result, :food) do
      [food | _rest] ->
        result
        |> Helpers.consume(food)
        |> Map.merge(%{canonical_food: food.value, canonical_food_id: food.meta[:food_id]})

      [] ->
        assign_implied_food(result, head_token)
    end
  end

  defp assign_implied_food(result, %{meta: %{implied_food: implied} = meta}) do
    result
    |> Map.merge(%{canonical_food: implied, canonical_food_id: meta[:implied_food_id]})
    |> Result.penalize(@implied_food_penalty, %{
      stage: :rule,
      rule: __MODULE__,
      implied_food: implied
    })
  end

  defp assign_implied_food(result, _token), do: result
end
