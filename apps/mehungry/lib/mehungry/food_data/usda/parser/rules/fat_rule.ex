defmodule Mehungry.FoodData.Usda.Parser.Rules.FatRule do
  @moduledoc """
  Pattern rule (not vocabulary — the values are open-ended numerics). Scans the
  normalized qualifier segments for a fat descriptor and sets `result.fat` to
  the whole matching segment:

    - fat content / ratio: "3.25% milkfat", "1% fat", "85% lean 15% fat"
    - fat trim level: "trimmed to 1/8 fat", "trimmed to 0 fat"

  The `%`, `.` and `/` survive because `Normalizer` preserves them. Only the
  first matching segment wins; its unknown tokens are consumed so the tail
  `ModifierRule` does not also sweep them into `processing_modifiers`.

  Bare word-forms ("whole", "lowfat") are deliberately excluded — "whole" is
  ambiguous ("Almonds, whole" is a whole nut, not full-fat) — so they remain
  modifiers.
  """

  @behaviour Mehungry.FoodData.Usda.Parser.Rules.Rule

  alias Mehungry.FoodData.Usda.Parser.Result
  alias Mehungry.FoodData.Usda.Parser.Rules.Helpers

  @patterns [
    ~r/\d+(?:\.\d+)?\s*%\s*(?:milkfat|fat|lean)/,
    ~r/\btrimmed to\b/
  ]

  @impl true
  def apply(%Result{fat: fat} = result) when not is_nil(fat), do: {:ok, result}

  def apply(%Result{} = result) do
    result.segments
    |> Enum.with_index()
    |> Enum.find(fn {phrases, _index} -> matches?(Enum.join(phrases, " ")) end)
    |> case do
      nil ->
        {:ok, result}

      {phrases, index} ->
        unknowns =
          Enum.filter(result.tokens, &(&1.segment == index and &1.type == :unknown))

        fat = Enum.join(phrases, " ")

        result =
          result
          |> Helpers.consume(unknowns)
          |> Map.put(:fat, fat)
          |> Helpers.trace_rule(__MODULE__, %{fat: fat})

        {:ok, result}
    end
  end

  defp matches?(text), do: Enum.any?(@patterns, &Regex.match?(&1, text))
end
