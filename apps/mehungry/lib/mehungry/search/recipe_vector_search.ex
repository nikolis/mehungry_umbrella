defmodule Mehungry.Search.RecipeVectorSearch do
  @moduledoc """
  Semantic recipe search using pgvector cosine similarity.

  Generates an embedding for the query via OpenAI and finds the closest
  recipe vectors stored in the `recipes.embedding` column.

  Falls back to full-text search if embedding generation fails.
  """

  import Ecto.Query
  require Logger

  alias Mehungry.{Repo, Search.RecipeSearch}
  alias Mehungry.Food.Recipe

  @default_limit 20

  # The embedding provider is a config seam (`:embedding_client`) so tests can
  # exercise the real vector-search path with a deterministic, offline stub
  # instead of degrading to strict full-text search. Defaults to the live
  # OpenAI-backed client.
  defp embedding_client,
    do: Application.get_env(:mehungry, :embedding_client, Mehungry.AI.EmbeddingClient)

  @doc """
  Search recipes by semantic similarity to `query_text`.

  Options:
    - `:user_id`     — restrict to recipes owned by this user (integer)
    - `:public_only` — when true, exclude `private` recipes (use for a catalog
      that spans users, so nobody's private recipes leak into another's plan)
    - `:limit`       — max results (default: 20)
    - `:exclude_ids` — list of recipe IDs to exclude

  Returns a list of maps: `%{id, title, difficulty, servings, nutrients}`
  (the stored per-recipe `nutrients` jsonb, so callers can derive calories
  without a second query). Falls back to full-text search if embedding is
  unavailable.
  """
  def search(query_text, opts \\ []) do
    user_id = Keyword.get(opts, :user_id)
    limit = Keyword.get(opts, :limit, @default_limit)
    exclude_ids = Keyword.get(opts, :exclude_ids, [])
    public_only = Keyword.get(opts, :public_only, false)

    case embedding_client().embed(query_text) do
      {:ok, vector} ->
        vector_search(vector, user_id, limit, exclude_ids, public_only)

      {:error, reason} ->
        Logger.warning("RecipeVectorSearch: embedding failed (#{reason}), falling back to FTS")
        fts_fallback(query_text, user_id, limit, public_only)
    end
  end

  defp vector_search(vector, user_id, limit, exclude_ids, public_only) do
    pg_vector = Pgvector.new(vector)

    base =
      from r in Recipe,
        where: not is_nil(r.embedding),
        order_by: fragment("embedding <=> ?", ^pg_vector),
        limit: ^limit,
        select: %{
          id: r.id,
          title: r.title,
          difficulty: r.difficulty,
          servings: r.servings,
          nutrients: r.nutrients
        }

    base
    |> maybe_filter_user(user_id)
    |> maybe_public_only(public_only)
    |> maybe_exclude_ids(exclude_ids)
    |> Repo.all()
  end

  defp fts_fallback(query_text, user_id, limit, public_only) do
    base_query =
      if user_id do
        from r in Recipe, where: r.user_id == ^user_id
      else
        Recipe
      end

    base_query
    |> maybe_public_only(public_only)
    |> RecipeSearch.run(query_text)
    |> limit(^limit)
    |> select([r], %{
      id: r.id,
      title: r.title,
      difficulty: r.difficulty,
      servings: r.servings,
      nutrients: r.nutrients
    })
    |> Repo.all()
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp maybe_public_only(query, true), do: where(query, [r], coalesce(r.private, false) == false)
  defp maybe_public_only(query, _), do: query

  defp maybe_exclude_ids(query, []), do: query
  defp maybe_exclude_ids(query, ids), do: where(query, [r], r.id not in ^ids)
end
