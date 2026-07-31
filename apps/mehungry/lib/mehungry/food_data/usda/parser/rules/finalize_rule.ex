defmodule Mehungry.FoodData.Usda.Parser.Rules.FinalizeRule do
  @moduledoc """
  Always the last rule: dedupes the accumulated lists, clamps confidence to
  [0.0, 1.0] and rounds it to 3 decimals.

  Also a safety net for vocabulary-only extensions: a `:processing` token no
  dedicated rule claimed (method seeded in the DB without a rule module) is
  still appended to `processing`, so DB rows alone are never silently lost —
  a dedicated `ProcessingMethodRule` module remains the documented path
  because it controls ordering.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @impl true
  def apply(result) do
    result =
      result
      |> sweep_unclaimed_processing()
      |> Map.update!(:processing, &Enum.uniq/1)
      |> reorder_modifiers()
      |> Map.update!(:confidence, &(&1 |> min(1.0) |> max(0.0) |> Float.round(3)))

    {:ok, result}
  end

  # Restores reading order: descriptor rules (leaf/seed/fruit) may have
  # appended their modifier before the ModifierRule sweep ran.
  defp reorder_modifiers(result) do
    positions =
      result.tokens
      |> Enum.reverse()
      |> Map.new(&{&1.value, &1.position})

    modifiers =
      result.processing_modifiers
      |> Enum.uniq()
      |> Enum.sort_by(&Map.get(positions, &1, :infinity))

    %{result | processing_modifiers: modifiers}
  end

  defp sweep_unclaimed_processing(result) do
    case Helpers.unconsumed(result, :processing) do
      [] ->
        result

      tokens ->
        # Vocabulary values are admin-controlled and finite, so the atom
        # table is bounded.
        methods = Enum.map(tokens, &String.to_atom(&1.value))

        result
        |> Helpers.consume(tokens)
        |> Map.update!(:processing, &Helpers.append_unique(&1, methods))
        |> Helpers.trace_rule(__MODULE__, %{unclaimed_processing: methods})
    end
  end
end
