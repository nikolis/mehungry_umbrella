defmodule USDA.Corpus.Vocabulary do
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  alias USDA.Corpus.Tokenizer

  def build_vacabulary_for_all_ingredients() do
    Repo.all(Ingredient)
    |> build()
  end

  def build(foods) do
    foods
    |> Stream.flat_map(fn food ->
      Tokenizer.tokenize(food.name)
    end)
    |> Enum.reduce(%{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
    |> Enum.sort_by(fn {_, count} -> -count end)
  end
end
