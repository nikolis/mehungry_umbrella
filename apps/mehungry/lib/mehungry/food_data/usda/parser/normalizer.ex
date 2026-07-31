defmodule Mehungry.FoodData.Usda.Parser.Normalizer do
  @moduledoc """
  Canonicalizes a phrase before classification: downcase, strip punctuation,
  collapse whitespace, singularize the last word ("Carrots" → "carrot",
  "baby carrots" → "baby carrot").

  `%`, `.` and `/` are preserved (everything else non-alphanumeric becomes a
  space) so numeric qualifiers survive for `Parser.Rules.FatRule`:
  "3.25% milkfat", "85% lean 15% fat", "trimmed to 1/8\" fat" → "trimmed to
  1/8 fat" (the inch mark is dropped, the fraction kept).

  Vocabulary aliases are passed through the same function when the in-memory
  `Mehungry.FoodData.Usda.Parser.Vocabulary` is built, so classifier lookups
  are always normalized-vs-normalized.

  Deliberately separate from `Mehungry.Food.Ingredient.normalize_string/1`:
  search normalization must not singularize.
  """

  @irregular %{"leaves" => "leaf", "halves" => "half", "loaves" => "loaf"}
  @keep_singular ~w(hummus couscous asparagus citrus molasses)

  @spec normalize(String.t()) :: String.t()
  def normalize(phrase) when is_binary(phrase) do
    phrase
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9%.\/\s]/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> singularize_last_word()
  end

  # Plurals of words ending in a sibilant (s/sh/ch/x/z) take "-es", so the
  # singular drops "es", not just "s" ("radishes" → "radish", "peaches" →
  # "peach", "boxes" → "box"). "-ses" is excluded: it is ambiguous
  # ("roses" → "rose" drops only "s"), and no USDA head noun needs it.
  @es_plural_endings ~w(ches shes xes zes)

  @doc """
  Deterministic singularization: irregulars map, keep-list, then suffix rules
  ("ies" → "y", "oes" → "o", sibilant "-es" → drop "es", keep "ss", drop
  trailing "s").
  """
  @spec singularize(String.t()) :: String.t()
  def singularize(word) do
    cond do
      Map.has_key?(@irregular, word) -> Map.fetch!(@irregular, word)
      word in @keep_singular -> word
      true -> singularize_suffix(word)
    end
  end

  defp singularize_suffix(word) do
    cond do
      # keeps short acronyms like "nfs" intact
      String.length(word) <= 3 -> word
      String.ends_with?(word, "ies") -> replace_suffix(word, 3, "y")
      String.ends_with?(word, "oes") -> replace_suffix(word, 2, "")
      String.ends_with?(word, @es_plural_endings) -> replace_suffix(word, 2, "")
      String.ends_with?(word, "ss") -> word
      String.ends_with?(word, "s") -> replace_suffix(word, 1, "")
      true -> word
    end
  end

  defp singularize_last_word(""), do: ""

  defp singularize_last_word(phrase) do
    {leading, [last]} = phrase |> String.split(" ") |> Enum.split(-1)
    Enum.join(leading ++ [singularize(last)], " ")
  end

  defp replace_suffix(word, chars_to_drop, replacement) do
    String.slice(word, 0, String.length(word) - chars_to_drop) <> replacement
  end
end
