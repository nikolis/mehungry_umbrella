defmodule USDA.Corpus.Tokenizer do
  @regex ~r/[a-z0-9%\/".-]+/

  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient

  def tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(",", " ")
    |> String.replace("(", " ")
    |> String.replace(")", " ")
    |> (&Regex.scan(@regex, &1)).()
    |> List.flatten()
  end

  def tokenize_ingredient_descriptions() do
    Repo.all(Ingredient)
    |> Enum.map(fn x -> tokenize(x.name) end)
  end
end
