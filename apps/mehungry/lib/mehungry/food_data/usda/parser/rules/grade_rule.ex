defmodule Mehungry.FoodData.Usda.Parser.Rules.GradeRule do
  @moduledoc """
  Claims the first unconsumed `:grade` token (USDA quality grade, e.g.
  "choice", "select", "prime", "grade a") and sets `result.grade`. Generic —
  any vocabulary grade value, default `nil`.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Helpers.unconsumed(result, :grade) do
      [] ->
        {:ok, result}

      [grade | _rest] = matched ->
        result =
          result
          |> Helpers.consume(matched)
          |> Map.put(:grade, grade.value)
          |> Helpers.trace_rule(__MODULE__, %{grade: grade.value})

        {:ok, result}
    end
  end
end
