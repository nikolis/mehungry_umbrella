defmodule Mehungry.Food.IngredientQueries do
  @moduledoc """
  Search queries over ingredients, recipes, and hashtags: full-text and
  trigram ingredient search (user and admin variants), recipe search, and
  hashtag lookups. Query-building helpers shared by the admin listings.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Categories,
    Ingredient,
    IngredientTranslation,
    Recipe,
    RecipeHashtag,
    RecipeIngredient,
    Recipes
  }

  alias Mehungry.Hashtag

  def search_hashtag(hashtag) do
    from(hashtag in Mehungry.Hashtag,
      where: hashtag.title == ^hashtag
    )
    |> Repo.one()
    |> Repo.preload(recipe_hashtags: [recipe: [recipe_ingredients: :ingredient]])
  end

  def search_hashtag1(hashtag) do
    hashtag = String.slice(hashtag, 1..-1//1)

    query =
      from(r in Recipe,
        join: rec_tag in RecipeHashtag,
        on: rec_tag.recipe_id == r.id,
        join: tag in Hashtag,
        on: tag.id == rec_tag.hashtag_id,
        where: tag.title == ^hashtag
      )

    {query, Recipes.list_recipes(query)}
  end

  def search_recipes_by_ingredient(ingredient_name) do
    ingredient_ids =
      Mehungry.Food.IngredientSearch.search(ingredient_name)
      |> Enum.map(& &1.id)

    query =
      from(r in Recipe,
        join: ri in RecipeIngredient,
        on: ri.recipe_id == r.id,
        where: ri.ingredient_id in ^ingredient_ids,
        distinct: true
      )

    {query, Recipes.list_recipes(query)}
  end

  def list_sample_recipes_for_ingredient(ingredient_id, limit \\ 4) do
    query =
      from(r in Recipe,
        join: ri in RecipeIngredient,
        on: ri.recipe_id == r.id,
        where: ri.ingredient_id == ^ingredient_id,
        limit: ^limit,
        distinct: true
      )

    Repo.all(query)
  end

  def search_recipe(query_string, language_name \\ nil)

  def search_recipe("", language_name) do
    query = from(r in Recipe)
    {query, Recipes.list_recipes(query, language_name)}
  end

  def search_recipe(query_string, language_name) do
    query = Mehungry.Search.RecipeSearch.run(Recipe, query_string)
    {query, Recipes.list_recipes(query, language_name)}
  end

  @doc """
  Counts every ingredient matching a search/filter query. The display `limit`,
  `offset` and `order_by` are stripped so the count reflects the true total
  number of matches, not just the page-sized slice that gets rendered.
  """
  def count_search_results(%Ecto.Query{} = query) do
    query
    |> exclude(:limit)
    |> exclude(:offset)
    |> exclude(:order_by)
    |> Repo.aggregate(:count)
  end

  def pagenate_query(query) do
    # return the next 50 posts

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 20
      )

    # assign the `after` cursor to a variable
    cursor_after = metadata.after

    results = Repo.preload(entries, [:category])

    {results, cursor_after}
  end

  def get_second_layer_foods_ids() do
    category_titles = [
      "Meals, Entrees, and Side Dishes",
      "Restaurant Foods",
      "Baked Products",
      "Snacks",
      "Sweets",
      "Baby Foods",
      "Breakfast Cereals",
      "Beverages"
    ]

    Enum.map(
      category_titles,
      fn x ->
        category = Categories.get_category_by_name(x)

        if(is_nil(category)) do
          nil
        else
          category.id
        end
      end
    )
    |> Enum.filter(fn x -> !is_nil(x) end)
  end

  def maybe_filter_by_classes(query, nil), do: query
  def maybe_filter_by_classes(query, []), do: query
  def maybe_filter_by_classes(query, [""]), do: query

  def maybe_filter_by_classes(query, classes) do
    from(i in query, where: i.food_class in ^classes)
  end

  def maybe_filter_by_data_types(query, nil), do: query
  def maybe_filter_by_data_types(query, []), do: query
  def maybe_filter_by_data_types(query, [""]), do: query

  def maybe_filter_by_data_types(query, data_types) do
    from(i in query, where: i.data_type in ^data_types)
  end

  @doc "Distinct non-nil `food_class` values, alphabetically — for admin filter options."
  def list_distinct_food_classes do
    from(i in Ingredient,
      where: not is_nil(i.food_class),
      distinct: true,
      select: i.food_class,
      order_by: i.food_class
    )
    |> Repo.all()
  end

  @doc "Distinct non-nil `data_type` values, alphabetically — for admin filter options."
  def list_distinct_data_types do
    from(i in Ingredient,
      where: not is_nil(i.data_type),
      distinct: true,
      select: i.data_type,
      order_by: i.data_type
    )
    |> Repo.all()
  end

  @doc """
  Excludes USDA "Branded" ingredients from a query. The `IS DISTINCT FROM` form
  keeps rows with a NULL `food_class` and matches the partial-index predicate
  on the `ingredients_*_active_idx` indexes, so the planner can use them.

  Applied to user-facing search entry points only — admin builders skip it so
  admins can still filter to `Branded`.
  """
  def exclude_branded(query) do
    from(i in query, where: fragment("? IS DISTINCT FROM 'Branded'", i.food_class))
  end

  def search_ingredient_search(search_term, classes \\ [], owner_id \\ nil) do
    secondary_ids = get_second_layer_foods_ids()

    from(i in Ingredient,
      where:
        fragment(
          "searchable @@ websearch_to_tsquery('english',?)",
          ^search_term
        ),
      limit: 20,
      order_by: {
        :desc,
        fragment(
          "ts_rank_cd(searchable, websearch_to_tsquery('english', ?), 4)",
          ^search_term
        )
      }
    )
    |> exclude_secondary_categories(secondary_ids, owner_id)
    |> filter_by_owner(owner_id)
    |> maybe_filter_by_classes(classes)
  end

  # Hides the composite/prepared USDA "second layer" categories (Snacks,
  # Beverages, Baked Products, …) from ingredient search — but never the
  # viewer's own private ingredients. A user deliberately picks the category
  # for an ingredient they created, so it must stay searchable for them
  # regardless of which category that is.
  defp exclude_secondary_categories(query, [], _owner_id), do: query

  defp exclude_secondary_categories(query, secondary_ids, nil) do
    from(i in query, where: i.category_id not in ^secondary_ids)
  end

  defp exclude_secondary_categories(query, secondary_ids, owner_id) do
    from(i in query,
      where: i.category_id not in ^secondary_ids or i.user_id == ^owner_id
    )
  end

  # Visibility filter: global rows (user_id IS NULL) always; plus the viewer's
  # own private rows when an id is given. Branches on nil (Ecto forbids `== nil`).
  defp filter_by_owner(query, nil), do: from(i in query, where: is_nil(i.user_id))

  defp filter_by_owner(query, owner_id) do
    from(i in query, where: is_nil(i.user_id) or i.user_id == ^owner_id)
  end

  def search_ingredient_alt_admin(search_term, classes \\ [], data_types \\ []) do
    query =
      search_ingredient_search(search_term, classes)
      |> maybe_filter_by_data_types(data_types)

    {query, pagenate_query(query), count_search_results(query)}
  end

  def search_ingredient_alt(search_term, classes \\ [], owner_id \\ nil) do
    result =
      search_ingredient_search(search_term, classes, owner_id)
      |> exclude_branded()
      |> Repo.all()

    Logger.info("Search ingredient: " <> search_term <> " resulted: " <> inspect(result))

    result
  end

  def search_ingredient_admin(search_term, classes \\ [], data_types \\ []) do
    query =
      search_ingredient_query(search_term, classes)
      |> maybe_filter_by_data_types(data_types)

    {query, pagenate_query(query), count_search_results(query)}
  end

  def search_ingredient_admin_translated(
        search_term,
        language_name,
        classes \\ [],
        data_types \\ []
      ) do
    ilike_term = "%#{search_term}%"

    # Unlimited set of matching translation ingredient_ids — used for the true
    # total count. The 20-row display slice is derived from it below.
    ids_base =
      from t in IngredientTranslation,
        where: t.language_name == ^language_name,
        select: t.ingredient_id

    ids_base =
      if search_term == "" do
        ids_base
      else
        from t in ids_base,
          where: fragment("unaccent(?) ILIKE unaccent(?)", t.name, ^ilike_term)
      end

    total_count =
      from(i in Ingredient, where: i.id in subquery(ids_base))
      |> maybe_filter_by_classes(classes)
      |> maybe_filter_by_data_types(data_types)
      |> Repo.aggregate(:count)

    # Top-20 display slice, ranked by relevance.
    ingredient_ids =
      from(t in ids_base,
        order_by: [
          desc:
            fragment(
              "CASE WHEN lower(unaccent(?)) = lower(unaccent(?)) THEN 1 ELSE 0 END",
              t.name,
              ^search_term
            ),
          asc: fragment("LENGTH(?)", t.name)
        ],
        limit: 20
      )
      |> Repo.all()

    ingredients =
      from(i in Ingredient, where: i.id in ^ingredient_ids)
      |> maybe_filter_by_classes(classes)
      |> maybe_filter_by_data_types(data_types)
      |> Repo.all()
      |> Repo.preload([:category])

    {nil, {ingredients, nil}, total_count}
  end

  def search_ingredient(search_term, classes \\ []) do
    Repo.all(search_ingredient_query(search_term, classes))
    |> Repo.preload([:category, :measurement_unit])
  end

  def search_ingredient_query(search_term, classes \\ []) do
    ilike_search_term = "%#{search_term}%"

    query =
      from(
        ingredient in Ingredient,
        where:
          fragment("? % ?", ^search_term, ingredient.name) or
            ilike(ingredient.name, ^ilike_search_term),
        order_by: {:desc, fragment("? % ?", ^search_term, ingredient.name)},
        limit: 20
      )
      |> maybe_filter_by_classes(classes)

    query
  end

  def search_ingredient3(search_term) do
    ilike_search_term = "%#{search_term}%"

    query =
      from(
        ingredient in Ingredient,
        where:
          ingredient.category_id != 212 and ingredient.category_id != 197 and
            ingredient.category_id != 192 and ingredient.category_id != 193 and
            ingredient.category_id != 194 and ilike(ingredient.name, ^ilike_search_term),
        order_by: {:desc, fragment("? % ?", ^search_term, ingredient.name)}
      )

    Repo.all(query)
  end

  def search_ingredient2(search_term) do
    search_term = "%" <> search_term <> "%"

    query =
      from ingredient in Ingredient,
        where:
          ingredient.category_id != 212 and ingredient.category_id != 197 and
            ingredient.category_id != 192 and ingredient.category_id != 193 and
            ingredient.category_id != 194 and ilike(ingredient.name, ^search_term),
        limit: 20

    Repo.all(query)
    |> Repo.preload([:category, :measurement_unit])
    |> Enum.sort_by(fn x -> String.length(x.name) end)
  end
end
