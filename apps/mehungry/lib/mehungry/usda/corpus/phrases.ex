defmodule USDA.Corpus.Phrases do

  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

   def get_top_20_percent(items) when is_list(items) do
    # 1. Sort descending by price
    sorted = Enum.sort_by(items, fn {_, price} -> price end, :desc)

    # 2. Calculate how many items represent 20%
    count = length(sorted)
    take_count = ceil(count * 0.1)

    # 3. Take the top items
    Enum.take(sorted, take_count)
   end

  def word_entropies() do
    Repo.all(Ingredient)
    |> Enum.map(fn x -> x.name end)
    |> build_neighbor_counts()
    |> Enum.into(%{}, fn {word, neighbors} ->
      {word, entropy(neighbors)}
    end)
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
    |> get_top_20_percent()
  end

  def entropy(neighbor_counts) do
    total =
      neighbor_counts
      |> Map.values()
      |> Enum.sum()

    neighbor_counts
    |> Map.values()
    |> Enum.reduce(0.0, fn count, h ->
      p = count / total
      h - p * :math.log2(p)
    end)
  end

  def build_neighbor_counts(descriptions) do
    Enum.reduce(descriptions, %{}, fn desc, acc ->
      tokens = USDA.Corpus.Tokenizer.tokenize(desc)

      Enum.with_index(tokens)
      |> Enum.reduce(acc, fn {token, i}, acc ->
        neighbors =
          [
            Enum.at(tokens, i - 1),
            Enum.at(tokens, i + 1)
          ]
          |> Enum.reject(&is_nil/1)

        Enum.reduce(neighbors, acc, fn neighbor, acc ->
          update_in(acc, [Access.key(token, %{}), Access.key(neighbor, 0)], &((&1 || 0) + 1))
        end)
      end)
    end)
  end

  # For this scneario in order to stay tuned with the prevailing terminology we 
  # we can state that it's usda record -> Ingredient is treated as a Document. 
  def build_document_frequency() do
    Repo.all(Ingredient)
    |> Enum.reduce(%{}, fn food, acc ->
      tokens =
        food.name
        |> USDA.Corpus.Tokenizer.tokenize()
        |> MapSet.new()

      Enum.reduce(tokens, acc, fn token, acc ->
        Map.update(acc, token, 1, &(&1 + 1))
      end)
    end)
  end

  def build_bigrams_for_all_ingredients() do
    Repo.all(Ingredient)
    |> build_bigrams()
  end

  def build_ngrams_for_all_ingredients(n) do
    Repo.all(Ingredient)
    |> build_ngrams(n)
  end

  def build_trigrams_for_all_ingredients() do
    Repo.all(Ingredient)
    |> build_trigrams()
  end

  def build_ngrams(foods, n) do
    foods
    |> Stream.flat_map(fn food ->
      food.name
      |> USDA.Corpus.Tokenizer.tokenize()
      |> USDA.Corpus.Phrases.ngrams(n)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
  end

  def build_trigrams(foods) do
    foods
    |> Stream.flat_map(fn food ->
      food.name
      |> USDA.Corpus.Tokenizer.tokenize()
      |> USDA.Corpus.Phrases.ngrams(3)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
  end

  def build_bigrams(foods) do
    foods
    |> Stream.flat_map(fn food ->
      food.name
      |> USDA.Corpus.Tokenizer.tokenize()
      |> USDA.Corpus.Phrases.ngrams(2)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_key, value} -> value end, :desc)
  end

  def ngrams(tokens, n) do
    tokens
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(&List.to_tuple/1)
  end

  def bigrams(tokens), do: ngrams(tokens, 2)

  def trigrams(tokens), do: ngrams(tokens, 3)
end
