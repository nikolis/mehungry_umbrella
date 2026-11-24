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
  alias Mehungry.Accounts.UserRecipe
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
    - `:ranked_for_user` — a user id: search that user's **own** recipes first,
      then the public recipes they **saved**, then the rest of the **public**
      catalog, each tier ranked by similarity. Own + saved fill at most
      `limit - 5` slots, so public recipes always get a few; slots the public
      tier can't fill go back to own → saved. Results are ordered by tier and
      each carries `source: "own" | "saved" | "public"`.
      Never returns another user's private recipe.
    - `:public_only` — when true, exclude `private` recipes (use for a catalog
      that spans users, so nobody's private recipes leak into another's plan)
    - `:limit`       — max results (default: 20)
    - `:exclude_ids` — list of recipe IDs to exclude
    - `:meal_roles`  — list of meal roles (`Mehungry.Food.MealRoles`); keep only
      recipes holding at least one of them, **or** with no roles at all
      (unclassified recipes stay eligible). Applied in SQL, before `:limit`.
    - `:max_total_minutes` — keep only recipes whose prep + cook time
      (`Food.total_time_minutes/1`) is known and at most this many minutes. A
      recipe with no time is excluded. Applied in SQL, before `:limit`.
    - `:time_exempt_roles` — with `:max_total_minutes`, a recipe holding one of
      these roles is kept whatever its time (Dinner: any `dinner` dish).

  Returns a list of maps: `%{id, title, difficulty, servings, nutrients,
  total_minutes}` (the stored per-recipe `nutrients` jsonb, so callers can derive
  calories without a second query; `total_minutes` nil when unknown). Falls back
  to full-text search if embedding is unavailable.
  """
  def search(query_text, opts \\ []) do
    filters = %{
      user_id: Keyword.get(opts, :user_id),
      ranked_for_user: Keyword.get(opts, :ranked_for_user),
      limit: Keyword.get(opts, :limit, @default_limit),
      exclude_ids: Keyword.get(opts, :exclude_ids, []),
      public_only: Keyword.get(opts, :public_only, false),
      meal_roles: Keyword.get(opts, :meal_roles, []),
      max_total_minutes: Keyword.get(opts, :max_total_minutes),
      time_exempt_roles: Keyword.get(opts, :time_exempt_roles, [])
    }

    runner =
      case embedding_client().embed(query_text) do
        {:ok, vector} ->
          &vector_search(Pgvector.new(vector), &1, &2)

        {:error, reason} ->
          Logger.warning("RecipeVectorSearch: embedding failed (#{reason}), falling back to FTS")
          &fts_fallback(query_text, &1, &2)
      end

    case filters.ranked_for_user do
      nil -> runner.(Recipe, filters)
      user_id -> ranked_search(user_id, filters, runner)
    end
  end

  # Own → saved → public, each tier similarity-ranked. Own + saved may take at
  # most `limit - @public_reserve` slots so a large personal catalog never shuts
  # the public catalog out; whatever the public tier leaves unused is handed back
  # to own → saved in a second pass, so the limit is still filled when it can be.
  @public_reserve 5
  @tier_order %{"own" => 0, "saved" => 1, "public" => 2}

  defp ranked_search(user_id, filters, runner) do
    personal = [own: own_scope(user_id), saved: saved_scope(user_id)]
    personal_cap = max(filters.limit - @public_reserve, 0)

    []
    |> fill_tiers(personal, personal_cap, filters, runner)
    |> fill_tiers([public: public_scope(user_id)], filters.limit, filters, runner)
    |> fill_tiers(personal, filters.limit, filters, runner)
    |> Enum.sort_by(&Map.fetch!(@tier_order, &1.source))
  end

  # Appends each tier's results (tagged with `source`) until `cap` results are
  # held, skipping ids already held.
  defp fill_tiers(acc, tiers, cap, filters, runner) do
    Enum.reduce(tiers, acc, fn {source, scope}, acc ->
      remaining = cap - length(acc)

      if remaining <= 0 do
        acc
      else
        tier_filters = %{
          filters
          | limit: remaining,
            exclude_ids: filters.exclude_ids ++ Enum.map(acc, & &1.id)
        }

        acc ++ Enum.map(runner.(scope, tier_filters), &Map.put(&1, :source, to_string(source)))
      end
    end)
  end

  defp own_scope(user_id), do: from(r in Recipe, where: r.user_id == ^user_id)

  defp saved_scope(user_id) do
    saved_ids = from(ur in UserRecipe, where: ur.user_id == ^user_id, select: ur.recipe_id)

    from r in Recipe,
      where:
        r.id in subquery(saved_ids) and (r.user_id != ^user_id or is_nil(r.user_id)) and
          coalesce(r.private, false) == false
  end

  defp public_scope(user_id) do
    from r in Recipe,
      where: (r.user_id != ^user_id or is_nil(r.user_id)) and coalesce(r.private, false) == false
  end

  defp vector_search(pg_vector, scope, filters) do
    from(r in scope,
      where: not is_nil(r.embedding),
      order_by: fragment("embedding <=> ?", ^pg_vector),
      limit: ^filters.limit
    )
    |> maybe_filter_user(filters.user_id)
    |> maybe_public_only(filters.public_only)
    |> maybe_exclude_ids(filters.exclude_ids)
    |> maybe_meal_roles(filters.meal_roles)
    |> maybe_max_time(filters.max_total_minutes, filters.time_exempt_roles)
    |> select_result()
    |> exact_all()
  end

  # `recipes_embedding_idx` is ivfflat (lists = 100). When the planner uses it for
  # `ORDER BY embedding <=> … LIMIT n`, it probes ONE list by default and applies
  # the WHERE filters (owner, meal roles, time) afterwards — so a filtered search
  # (a person's own small catalog) can come back short or empty. Probing every
  # list makes the index scan exact; catalogs are small, so it stays cheap. Works
  # on any pgvector version (no reliance on 0.8's iterative scans).
  @ivfflat_lists 100

  defp exact_all(query) do
    {:ok, rows} =
      Repo.transaction(fn ->
        Repo.query!("SET LOCAL ivfflat.probes = #{@ivfflat_lists}")
        Repo.all(query)
      end)

    rows
  end

  defp fts_fallback(query_text, scope, filters) do
    scope
    |> maybe_filter_user(filters.user_id)
    |> maybe_public_only(filters.public_only)
    |> maybe_exclude_ids(filters.exclude_ids)
    |> maybe_meal_roles(filters.meal_roles)
    |> maybe_max_time(filters.max_total_minutes, filters.time_exempt_roles)
    |> RecipeSearch.run(query_text)
    |> limit(^filters.limit)
    |> select_result()
    |> Repo.all()
  end

  defp select_result(query) do
    select(query, [r], %{
      id: r.id,
      title: r.title,
      difficulty: r.difficulty,
      servings: r.servings,
      nutrients: r.nutrients,
      total_minutes:
        fragment(
          "NULLIF(COALESCE(?, 0) + COALESCE(?, 0), 0)",
          r.preperation_time_lower_limit,
          r.cooking_time_lower_limit
        )
    })
  end

  # Same definition as `Food.total_time_minutes/1`: prep + cook lower limits, nil
  # (here: excluded) when neither is set.
  defp maybe_max_time(query, nil, _exempt), do: query

  defp maybe_max_time(query, max, exempt) when is_integer(max) do
    where(
      query,
      [r],
      fragment(
        "(NULLIF(COALESCE(?, 0) + COALESCE(?, 0), 0) <= ?) OR EXISTS (SELECT 1 FROM recipe_meal_roles m WHERE m.recipe_id = ? AND m.role = ANY(?))",
        r.preperation_time_lower_limit,
        r.cooking_time_lower_limit,
        ^max,
        r.id,
        type(^exempt, {:array, :string})
      )
    )
  end

  defp maybe_filter_user(query, nil), do: query
  defp maybe_filter_user(query, user_id), do: where(query, [r], r.user_id == ^user_id)

  defp maybe_public_only(query, true), do: where(query, [r], coalesce(r.private, false) == false)
  defp maybe_public_only(query, _), do: query

  defp maybe_meal_roles(query, roles) when roles in [nil, []], do: query

  defp maybe_meal_roles(query, roles) do
    where(
      query,
      [r],
      fragment(
        "(NOT EXISTS (SELECT 1 FROM recipe_meal_roles m WHERE m.recipe_id = ?) OR EXISTS (SELECT 1 FROM recipe_meal_roles m WHERE m.recipe_id = ? AND m.role = ANY(?)))",
        r.id,
        r.id,
        type(^roles, {:array, :string})
      )
    )
  end

  defp maybe_exclude_ids(query, []), do: query
  defp maybe_exclude_ids(query, ids), do: where(query, [r], r.id not in ^ids)
end
