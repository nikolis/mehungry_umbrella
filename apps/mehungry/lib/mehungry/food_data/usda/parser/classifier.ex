defmodule Mehungry.FoodData.Usda.Parser.Classifier do
  @moduledoc """
  Assigns a `Mehungry.FoodData.Usda.Parser.Token` type to every phrase in
  `result.segments` by looking it up in the vocabulary.

  Per phrase: whole-phrase lookup first (catches multi-word aliases like
  "kosher dill" and "alcoholic beverage"), otherwise greedy left-to-right word
  windows from `vocabulary.max_alias_words` down to 1. An unmatched word
  becomes an `:unknown` token and multiplies confidence by
  #{inspect(0.8)}; `:noise` vocabulary entries are dropped silently with no
  penalty.
  """

  alias Mehungry.FoodData.Usda.Parser.{Result, Token, Vocabulary}

  @unknown_penalty 0.8

  @spec classify(Result.t(), Vocabulary.t()) :: Result.t()
  def classify(%Result{} = result, %Vocabulary{} = vocab) do
    {reversed_tokens, result} =
      result.segments
      |> Enum.with_index()
      |> Enum.reduce({[], result}, fn {phrases, segment}, acc ->
        Enum.reduce(phrases, acc, fn phrase, {tokens, res} ->
          classify_phrase(phrase, segment, vocab, tokens, res)
        end)
      end)

    tokens =
      reversed_tokens
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.map(fn {token, position} -> %{token | position: position} end)

    %{result | tokens: tokens}
    |> Result.put_trace(%{
      stage: :classifier,
      tokens: Enum.map(tokens, &%{type: &1.type, value: &1.value})
    })
  end

  defp classify_phrase(phrase, segment, vocab, tokens, result) do
    case Vocabulary.lookup(vocab, phrase) do
      %{type: :noise} -> {tokens, result}
      %{} = entry -> {[token(entry, phrase, segment) | tokens], result}
      nil -> classify_words(String.split(phrase, " "), segment, vocab, tokens, result)
    end
  end

  defp classify_words([], _segment, _vocab, tokens, result), do: {tokens, result}

  defp classify_words([word | rest] = words, segment, vocab, tokens, result) do
    width = min(vocab.max_alias_words, length(words))

    case match_window(words, width, vocab) do
      {%{type: :noise}, _matched, remaining} ->
        classify_words(remaining, segment, vocab, tokens, result)

      {entry, matched, remaining} ->
        classify_words(
          remaining,
          segment,
          vocab,
          [token(entry, matched, segment) | tokens],
          result
        )

      nil ->
        result = Result.penalize(result, @unknown_penalty, %{stage: :classifier, unknown: word})
        unknown = %Token{type: :unknown, raw: word, value: word, segment: segment}
        classify_words(rest, segment, vocab, [unknown | tokens], result)
    end
  end

  defp match_window(_words, 0, _vocab), do: nil

  defp match_window(words, width, vocab) do
    candidate = words |> Enum.take(width) |> Enum.join(" ")

    case Vocabulary.lookup(vocab, candidate) do
      nil -> match_window(words, width - 1, vocab)
      entry -> {entry, candidate, Enum.drop(words, width)}
    end
  end

  defp token(entry, raw, segment) do
    %Token{type: entry.type, raw: raw, value: entry.value, segment: segment, meta: entry.meta}
  end
end
