defmodule Mehungry.FoodData.Usda.Parser.Rules.PortionRule do
  @moduledoc """
  Sweeps every unconsumed `:portion` token (tissue/skin selection, e.g. "meat
  only", "skinless", "separable lean and fat", "flesh and skin") into
  `result.portion`. A description can carry several ("meat only" + "skinless"),
  so this appends to a list (reading order preserved), default `[]`.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    case Helpers.unconsumed(result, :portion) do
      [] ->
        {:ok, result}

      tokens ->
        values = tokens |> Enum.sort_by(& &1.position) |> Enum.map(& &1.value)

        result =
          result
          |> Helpers.consume(tokens)
          |> Map.update!(:portion, &Helpers.append_unique(&1, values))
          |> Helpers.trace_rule(__MODULE__, %{portion: values})

        {:ok, result}
    end
  end
end
