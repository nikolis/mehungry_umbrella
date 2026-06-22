defmodule Mehungry.Search.RecipeVectorSearch do
  @moduledoc """
  Semantic recipe search using pgvector cosine similarity.

  Generates an embedding for the query via OpenAI and finds the closest
  recipe vectors stored in the `recipes.embedding` column.

  Falls back to full-text search if embedding generation fails.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.{Repo, AI.EmbeddingClient, Search.RecipeSearch}
  alias Mehungry.Food.Recipe

  @default_limit 20

  @doc """
  Search recipes by semantic similarity to `query_text`.

  Options:
    - `:user_id`     — restrict to recipes owned by this user (integer)
    - `:limit`       — max results (default: 20)
    - `:exclude_ids` — list of recipe IDs to exclude

  Returns a list of maps: `%{id, title, difficulty, servings}`.
  Falls back to full-text search if embedding is unavailable.
  """
  def search(query_text, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    limit = Keyword.get(opts, :limit, @default_limit)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])

    case EmbeddingClient.embed(query_text) do
      {:ok, vector} ->
        vector_search(vector, user_id, limit, exclude_ids)

      {:error, reason} ->
        Logger.warning("RecipeVectorSearch: embedding failed (#{reason}), falling back to FTS")
        fts_fallback(query_text, user_id, limit)
    end
  end

  defp vector_search(vector, user_id, limit, exclude_ids) do
    pg_vector = Pgvector.new(vector)

    base =
      from r in Recipe,
        where: not is_nil(r.embedding),
        order_by: fragment("embedding <=> ?", ^pg_vector),
        limit: ^limit,
        select: %{id: r.id, title: r.title, difficulty: r.difficulty, servings: r.servings}

    base
    |> maybe_filter_user(user_id)
    |> maybe_exclude_ids(exclude_ids)
    |> Repo.all()
  end

  defp fts_fallback(query_text, user_id, limit) do
    base_query =
      if user_id do
        from r in Recipe, where: r.user_id == ^user_id
      else
        Recipe
      end

    base_query
    |> RecipeSearch.run(query_text)
    |> limit(^limit)
    |> select([r], %{id: r.id, title: r.title, difficulty: r.difficulty, servings: r.servings})
    |> Repo.all()
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp maybe_exclude_ids(query, []), do: query
  defp maybe_exclude_ids(query, ids), do: where(query, [r], r.id not in ^ids)
end
