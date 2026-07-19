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

  def search_ingredient_search(search_term, classes \\ []) do
    secondary_ids = get_second_layer_foods_ids()

    from(i in Ingredient,
      where:
        i.category_id not in ^secondary_ids and
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
    |> maybe_filter_by_classes(classes)
  end

  def search_ingredient_alt_admin(search_term, classes \\ []) do
    {search_ingredient_search(search_term, classes),
     pagenate_query(search_ingredient_search(search_term, classes))}
  end

  def search_ingredient_alt(search_term, classes \\ []) do
    result = Repo.all(search_ingredient_search(search_term, classes))
    Logger.info("Search ingredient: " <> search_term <> " resulted: " <> inspect(result))

    result
  end

  def search_ingredient_admin(search_term, classes \\ []) do
    query = search_ingredient_query(search_term, classes)
    {query, pagenate_query(query)}
  end

  def search_ingredient_admin_translated(search_term, language_name, classes \\ []) do
    ilike_term = "%#{search_term}%"

    base =
      from t in IngredientTranslation,
        where: t.language_name == ^language_name,
        order_by: [
          desc:
            fragment(
              "CASE WHEN lower(unaccent(?)) = lower(unaccent(?)) THEN 1 ELSE 0 END",
              t.name,
              ^search_term
            ),
          asc: fragment("LENGTH(?)", t.name)
        ],
        limit: 20,
        select: t.ingredient_id

    base =
      if search_term == "" do
        base
      else
        from t in base,
          where: fragment("unaccent(?) ILIKE unaccent(?)", t.name, ^ilike_term)
      end

    ingredient_ids = Repo.all(base)

    ingredients =
      from(i in Ingredient, where: i.id in ^ingredient_ids)
      |> maybe_filter_by_classes(classes)
      |> Repo.all()
      |> Repo.preload([:category])

    {nil, {ingredients, nil}}
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
