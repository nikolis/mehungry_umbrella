defmodule Mehungry.FoodData.Usda.Parser.Rules.ModifierRule do
  @moduledoc """
  Tail sweep: any remaining unconsumed `:modifier` token becomes a
  processing modifier, and so does any `:unknown` token in a qualifier
  segment (≥ 1) — its confidence penalty was already applied by the
  classifier, so keeping the word as a modifier degrades gracefully instead
  of losing information.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    unknowns = Enum.filter(Helpers.unconsumed(result, :unknown), &(&1.segment >= 1))
    tokens = Enum.sort_by(Helpers.unconsumed(result, :modifier) ++ unknowns, & &1.position)

    case tokens do
      [] ->
        {:ok, result}

      _ ->
        values = Enum.map(tokens, & &1.value)

        result =
          result
          |> Helpers.consume(tokens)
          |> Map.update!(:processing_modifiers, &Helpers.append_unique(&1, values))
          |> Helpers.trace_rule(__MODULE__, %{modifiers: values})

        {:ok, result}
    end
  end
end
