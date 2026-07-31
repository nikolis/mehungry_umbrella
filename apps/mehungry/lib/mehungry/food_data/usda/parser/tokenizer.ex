defmodule Mehungry.FoodData.Usda.Parser.Tokenizer do
  @moduledoc """
  Splits a USDA food description into segments of phrases.

  USDA descriptions follow a `"Primary, qualifier, qualifier"` grammar, so the
  comma is the semantic boundary: segment 0 is the head noun phrase, the rest
  are qualifiers. Within a segment, ` or `/`;`/` with ` split phrases
  ("dill or kosher dill" → two phrases; "raw with skin" → ["raw", "skin"]), and
  parenthesized synonyms are lifted into sibling phrases of the same segment
  ("Coriander (cilantro)" → ["coriander", "cilantro"]).

  `" and "` is deliberately **not** a splitter: USDA uses it inside single
  qualifier concepts ("separable lean and fat", "meat and skin") and compound
  names ("macaroni and cheese"), which must stay whole to classify.

  Output preserves the raw text; normalization happens in
  `Mehungry.FoodData.Usda.Parser.Normalizer`.
  """

  @phrase_splitter ~r/\s+or\s+|\s+with\s+|\s*;\s*/i
  @parenthetical ~r/\(([^)]*)\)/

  @spec tokenize(String.t()) :: [[String.t()]]
  def tokenize(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&split_phrases/1)
    |> Enum.reject(&(&1 == []))
  end

  defp split_phrases(segment) do
    {stripped, lifted} = lift_parentheticals(segment)

    [stripped | lifted]
    |> Enum.flat_map(&Regex.split(@phrase_splitter, &1))
    |> Enum.map(&(&1 |> String.replace(~r/\s+/, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
  end

  defp lift_parentheticals(segment) do
    lifted =
      @parenthetical
      |> Regex.scan(segment)
      |> Enum.map(fn [_full, inner] -> inner end)

    {Regex.replace(@parenthetical, segment, " "), lifted}
  end
end
