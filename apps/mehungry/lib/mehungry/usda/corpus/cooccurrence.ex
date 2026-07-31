defmodule USDA.Corpus.Cooccurrence do
  @moduledoc """
  Builds token co-occurrence statistics over the USDA ingredient corpus — each
  `Mehungry.Food.Ingredient`'s `name`, tokenized by `USDA.Corpus.Tokenizer`.

  Part of the `USDA.Corpus.*` corpus-analysis toolkit (see `README.md` in this
  directory): an offline exploration of the ingredient-name vocabulary,
  **separate from** the deterministic `Mehungry.FoodData.Usda.Parser`.

  Supports two modes:

    * :document - every unique token in a document (ingredient name) co-occurs
      with every other
    * :window   - tokens co-occur only within a configurable radius

  Returns a neighbor dictionary:

      %{
        "beef" => %{
          "raw" => 4211,
          "choice" => 732,
          "loin" => 851
        }
      }
  """

  alias USDA.Corpus.Tokenizer

  @type matrix :: %{String.t() => %{String.t() => non_neg_integer()}}

  @doc """
  Build a co-occurrence matrix.

      build(foods)

      build(foods, mode: :window, radius: 2)
  """
  def build(foods, opts \\ []) do
    mode = Keyword.get(opts, :mode, :document)
    radius = Keyword.get(opts, :radius, 2)

    Enum.reduce(foods, %{}, fn food, matrix ->
      tokens =
        food.name
        |> Tokenizer.tokenize()

      pairs =
        case mode do
          :document ->
            document_pairs(tokens)

          :window ->
            window_pairs(tokens, radius)
        end

      Enum.reduce(pairs, matrix, &update_matrix/2)
    end)
  end

  ## ------------------------------------------------------------------
  ## Pair generation
  ## ------------------------------------------------------------------

  defp document_pairs(tokens) do
    tokens
    |> Enum.uniq()
    |> combinations()
  end

  defp combinations([]), do: []

  defp combinations([head | tail]) do
    Enum.map(tail, fn token ->
      canonical_pair(head, token)
    end) ++ combinations(tail)
  end

  defp window_pairs(tokens, radius) do
    size = length(tokens)

    Enum.with_index(tokens)
    |> Enum.flat_map(fn {token, index} ->
      left = max(0, index - radius)
      right = min(size - 1, index + radius)

      Enum.flat_map(left..right, fn i ->
        cond do
          i == index ->
            []

          true ->
            [canonical_pair(token, Enum.at(tokens, i))]
        end
      end)
    end)
  end

  ## ------------------------------------------------------------------
  ## Matrix updates
  ## ------------------------------------------------------------------

  defp update_matrix({a, b}, matrix) do
    matrix
    |> increment(a, b)
    |> increment(b, a)
  end

  defp increment(matrix, token, neighbor) do
    neighbors = Map.get(matrix, token, %{})

    neighbors =
      Map.update(
        neighbors,
        neighbor,
        1,
        &(&1 + 1)
      )

    Map.put(matrix, token, neighbors)
  end

  ## ------------------------------------------------------------------
  ## Helpers
  ## ------------------------------------------------------------------

  defp canonical_pair(a, b) when a <= b, do: {a, b}
  defp canonical_pair(a, b), do: {b, a}
end
