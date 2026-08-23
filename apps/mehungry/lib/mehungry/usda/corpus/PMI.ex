defmodule USDA.Corpus.PMI do
  @moduledoc """
    Pointwise Mutual Information, a statistical measure used to evaluate how strongly two words or terms co-occur within a text collection. It compares their actual observed frequency of appearing together against what you would expect if they were completely independent.
  """

  def build_pmi_for_all_ingredients() do
    vocabulary =
      USDA.Corpus.Vocabulary.build_vacabulary_for_all_ingredients()
      |> Map.new()

    bigrams = USDA.Corpus.Phrases.build_bigrams_for_all_ingredients()
    build_pmi(vocabulary, bigrams)
  end

  def build_pmi(vocabulary, bigrams) do
    total_pairs =
      Enum.reduce(bigrams, 0, fn {_, count}, acc ->
        acc + count
      end)

    total_tokens =
      Enum.reduce(vocabulary, 0, fn {_, count}, acc ->
        acc + count
      end)

    Enum.map(bigrams, fn {{a, b}, pair_count} ->
      left = Map.fetch!(vocabulary, a)
      right = Map.fetch!(vocabulary, b)

      {
        {a, b},
        USDA.Corpus.PMI.score(
          pair_count,
          left,
          right,
          total_pairs,
          total_tokens
        )
      }
    end)
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
  end

  # PMI mixes two probability spaces: the joint distribution lives over bigram
  # observations (`total_pairs`), while each marginal lives over the unigram
  # token distribution (`total_tokens`). Normalizing all three by the same
  # denominator would skew every score, so the marginals use `total_tokens`.
  def score(
        pair_count,
        left_count,
        right_count,
        total_pairs,
        total_tokens
      ) do
    p_xy = pair_count / total_pairs
    p_x = left_count / total_tokens
    p_y = right_count / total_tokens

    :math.log(p_xy / (p_x * p_y))
  end
end
