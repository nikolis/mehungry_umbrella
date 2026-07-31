defmodule Mehungry.FoodData.Usda.Parser.Rules.OilRule do
  @moduledoc """
  Head template `"Oil, <ingredient>"`: a head-position `:processing` token
  "oil" means the description names an oil *extracted from* the food in the
  following segments — `"Oil, corn"` → food corn, processing `[:oil]`, never
  food "oil".
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Result
  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(%Result{} = result) do
    case head_oil_token(result) do
      nil ->
        {:ok, result}

      token ->
        result =
          result
          |> Helpers.consume(token)
          |> Map.update!(:processing, &Helpers.append_unique(&1, :oil))
          |> assign_food()

        {:ok,
         Helpers.trace_rule(result, __MODULE__, %{processing: :oil, food: result.canonical_food})}
    end
  end

  defp head_oil_token(result) do
    result
    |> Helpers.unconsumed(:processing)
    |> Enum.find(&(&1.value == "oil" and &1.segment == 0 and &1.meta[:head] == true))
  end

  defp assign_food(result) do
    case Enum.filter(Helpers.unconsumed(result, :food), &(&1.segment > 0)) do
      [food | _rest] ->
        result
        |> Helpers.consume(food)
        |> Map.merge(%{canonical_food: food.value, canonical_food_id: food.meta[:food_id]})

      [] ->
        result
    end
  end
end
