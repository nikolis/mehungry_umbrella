defmodule Mehungry.AI.EmbeddingClientStub do
  @moduledoc """
  Deterministic, offline stand-in for `Mehungry.AI.EmbeddingClient` used by the
  meal-plan eval so `RecipeVectorSearch` runs its real vector-search path without
  an OpenAI key (instead of degrading to strict full-text search, which misses
  the agent's natural-language queries).

  `embed/1` produces a normalized 1536-dim bag-of-words hashing vector: each
  lowercased token is hashed to a dimension and accumulated. Query and recipe
  text embedded through the same function share the space, so cosine similarity
  ranks recipes by lexical overlap — "hearty mediterranean dinner" lands the
  Mediterranean dinner recipe near the top, breakfast queries rank breakfast
  recipes, etc. Wired in via `config :mehungry, :embedding_client` in test.
  """

  @dims 1536

  @doc "Mirrors EmbeddingClient.embed/1 — returns {:ok, [float]} (1536 dims)."
  def embed(text) when is_binary(text), do: {:ok, vector(text)}

  @doc "The raw 1536-dim vector for `text` (used to seed recipe embeddings too)."
  def vector(text) when is_binary(text) do
    counts =
      text
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)
      |> Enum.reduce(%{}, fn token, acc ->
        idx = :erlang.phash2(token, @dims)
        Map.update(acc, idx, 1.0, &(&1 + 1.0))
      end)

    dense = for i <- 0..(@dims - 1), do: Map.get(counts, i, 0.0)
    normalize(dense)
  end

  # L2-normalize so cosine distance is well-behaved; zero vector (no tokens)
  # stays zero.
  defp normalize(vec) do
    norm = vec |> Enum.reduce(0.0, fn x, acc -> acc + x * x end) |> :math.sqrt()
    if norm == 0.0, do: vec, else: Enum.map(vec, &(&1 / norm))
  end
end
