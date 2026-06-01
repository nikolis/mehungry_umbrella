defmodule Mehungry.Food.IngredientSearch do
  # Trigger the fuzzy fallback when prefix results fall below this count.
  @prefix_sufficient 10
  # Upper bound on total results returned.
  @max_results 20
  # Minimum pg_trgm word_similarity score to include a fuzzy result.
  @fuzzy_threshold 0.3

  @moduledoc """
  Ranked ingredient search backed by the local USDA database.

  ## Search strategy

  ### Primary: prefix match on `search_name`

  `search_name` is the lowercased, punctuation-stripped version of the USDA
  ingredient name stored on each row (e.g. "Salt, table" → "salt table").
  Prefix matching on this column is fast (btree-friendly) and handles the
  USDA "Primary, qualifier" naming convention well: a user typing "salt"
  will hit every ingredient whose primary word is "salt".

  Multi-word queries (e.g. "olive oil") additionally match rows where all
  words appear in any order, so both "Olive oil, salad or cooking" and
  "Oil, olive" are found.

  ### Ranking (within prefix results)

  1. **Exact match** — `search_name` equals the full normalized query.
  2. **Word similarity** (pg_trgm `word_similarity`) — scores how closely
     the query matches the single best-matching word in the ingredient name.
     This naturally promotes "Salt, table" for the query "salt" because the
     word "Salt" is a perfect match.
  3. **Short name first** — "Salt, table" (10 chars) beats
     "Salt substitute, principal ingredient…" (50+ chars).  Shorter USDA
     names are generally the canonical, least-qualified forms.
  4. **USDA food class preference** — Foundation > SR Legacy > Survey (FNDDS)
     > Experimental > other.  Foundation data is the most complete and
     analytically verified.
  5. **Alphabetical tiebreak** — stable ordering for equal-scored rows.

  ### Fuzzy fallback (pg_trgm `word_similarity`)

  When fewer than #{@prefix_sufficient} prefix results are found, the search
  supplements with trigram-similarity matches on the `name` column (which
  has a GIN trigram index).  This handles typos and partial words (e.g.
  "olivve" → "Olive oil").  The fallback threshold is #{@fuzzy_threshold}.
  """

  import Ecto.Query
  alias Mehungry.Repo
  alias Mehungry.Food.Ingredient
  alias Mehungry.Food.IngredientTranslation

  # ═════════════════════════════════════════════════════════════════════════
  # Public API
  # ═════════════════════════════════════════════════════════════════════════

  @doc """
  Searches ingredients and returns up to #{@max_results} results ranked by
  relevance.

  Accepts an optional `classes` list to restrict results to specific USDA
  food classes (e.g. `["Foundation", "SR Legacy"]`).
  """
  def search(search_term, classes \\ []) do
    normalized = Ingredient.normalize_string(search_term)

    if normalized == "" do
      []
    else
      prefix_results = run_prefix_query(normalized, search_term, classes)

      if length(prefix_results) >= @prefix_sufficient do
        prefix_results
      else
        needed = @max_results - length(prefix_results)
        exclude_ids = Enum.map(prefix_results, & &1.id)
        fuzzy_results = run_fuzzy_query(normalized, exclude_ids, needed, classes)
        prefix_results ++ fuzzy_results
      end
    end
  end

  @doc "Returns only `%{id: id, name: name}` maps — lightweight version for select dropdowns."
  def search_for_select(search_term, classes \\ []) do
    search(search_term, classes)
    |> Enum.map(fn i -> %{id: i.id, name: i.name} end)
  end

  @doc """
  Searches ingredient names via their translations for the given language code.
  Returns `%{id: ingredient_id, name: translated_name}` maps so the result is
  drop-in compatible with `search/1` for use in select dropdowns.
  """
  def search_in_language(search_term, language_name) when is_binary(search_term) do
    normalized = String.trim(search_term)

    if normalized == "" do
      from(t in IngredientTranslation,
        where: t.language_name == ^language_name,
        join: i in Ingredient,
        on: i.id == t.ingredient_id,
        order_by: [asc: fragment("LENGTH(?)", t.name)],
        limit: @max_results,
        select: %{id: t.ingredient_id, name: t.name}
      )
      |> Repo.all()
    else
      from(t in IngredientTranslation,
        where: t.language_name == ^language_name,
        where: ilike(t.name, ^"%#{normalized}%"),
        join: i in Ingredient,
        on: i.id == t.ingredient_id,
        order_by: [
          desc: fragment("CASE WHEN lower(?) = lower(?) THEN 1 ELSE 0 END", t.name, ^normalized),
          asc: fragment("LENGTH(?)", t.name)
        ],
        limit: @max_results,
        select: %{id: t.ingredient_id, name: t.name}
      )
      |> Repo.all()
    end
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Query builders
  # ═════════════════════════════════════════════════════════════════════════

  # Prefix search on the normalized search_name column with full ranking.
  # For multi-word terms the WHERE is broadened to include all-words-any-order
  # matches in addition to the strict phrase prefix.
  defp run_prefix_query(normalized, original_term, classes) do
    search_words = String.split(normalized, " ")

    where_clause = build_where(normalized, search_words)

    from(i in Ingredient,
      where: not is_nil(i.search_name),
      where: i.category_id not in ^get_excluded_category_ids(),
      where: ^where_clause,
      order_by: [
        # 1. Exact normalized match
        desc: fragment("CASE WHEN ? = ? THEN 1 ELSE 0 END", i.search_name, ^normalized),
        # 2. pg_trgm word similarity — perfect match on "salt" in "Salt, table" = 1.0
        desc: fragment("word_similarity(?, ?)", ^original_term, i.name),
        # 3. Shorter names are less qualified and therefore more canonical
        asc: fragment("LENGTH(?)", i.search_name),
        # 4. USDA data quality preference
        asc:
          fragment(
            """
            CASE ?
              WHEN 'Foundation'     THEN 1
              WHEN 'SR Legacy'      THEN 2
              WHEN 'Survey (FNDDS)' THEN 3
              WHEN 'Experimental'   THEN 4
              ELSE 5
            END
            """,
            i.food_class
          ),
        # 5. Stable alphabetical tiebreak
        asc: i.search_name
      ],
      limit: @max_results
    )
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # Single-word: plain prefix match.
  defp build_where(normalized, [_single_word]) do
    dynamic([i], ilike(i.search_name, ^"#{normalized}%"))
  end

  # Multi-word: phrase prefix OR all individual words present (any order).
  # The phrase prefix catches "olive oil sal..." while the all-words branch
  # catches "oil, olive" when the user types "olive oil".
  defp build_where(normalized, words) do
    phrase_prefix = dynamic([i], ilike(i.search_name, ^"#{normalized}%"))

    all_words =
      Enum.reduce(words, dynamic(true), fn word, acc ->
        dynamic([i], ^acc and ilike(i.search_name, ^"%#{word}%"))
      end)

    dynamic([i], ^phrase_prefix or ^all_words)
  end

  # Trigram word-similarity fallback.
  # Uses the GIN trigram index on `name` (created by ingredient_gin_trgm migration)
  # to efficiently find approximate matches when the prefix search comes up short.
  defp run_fuzzy_query(normalized, exclude_ids, limit, classes) do
    base =
      from i in Ingredient,
        where: not is_nil(i.search_name),
        where: i.category_id not in ^get_excluded_category_ids(),
        where:
          fragment(
            "word_similarity(?, ?) > ?",
            ^normalized,
            i.name,
            ^@fuzzy_threshold
          ),
        order_by: [
          desc: fragment("word_similarity(?, ?)", ^normalized, i.name),
          asc: fragment("LENGTH(?)", i.search_name),
          asc:
            fragment(
              """
              CASE ?
                WHEN 'Foundation'     THEN 1
                WHEN 'SR Legacy'      THEN 2
                WHEN 'Survey (FNDDS)' THEN 3
                WHEN 'Experimental'   THEN 4
                ELSE 5
              END
              """,
              i.food_class
            )
        ],
        limit: ^limit

    # Exclude IDs already returned by the prefix search.
    base =
      if exclude_ids == [] do
        base
      else
        from i in base, where: i.id not in ^exclude_ids
      end

    base
    |> maybe_filter_by_classes(classes)
    |> Repo.all()
  end

  # ═════════════════════════════════════════════════════════════════════════
  # Helpers
  # ═════════════════════════════════════════════════════════════════════════

  defp maybe_filter_by_classes(query, nil), do: query
  defp maybe_filter_by_classes(query, []), do: query
  defp maybe_filter_by_classes(query, [""]), do: query

  defp maybe_filter_by_classes(query, classes) do
    from i in query, where: i.food_class in ^classes
  end

  # Returns category IDs to exclude from all searches.
  # Extend this to filter out secondary/derived food categories.
  defp get_excluded_category_ids, do: []
end
