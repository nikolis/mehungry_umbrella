defmodule Mehungry.Food.Recipes do
  @moduledoc """
  Recipe CRUD, listing/pagination, per-user recipe queries and counts,
  nutrition enrichment on save, and the recipes cache.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo
  alias Mehungry.Hashtag
  alias Mehungry.Food.{
    Categories,
    DietClassifier,
    Localization,
    NutrientClaims,
    Recipe,
    RecipeHashtag,
    RecipeSocialGraphic,
    Step,
    WeeklyPlanGraphic
  }

  # The recipes cache predates this module: entries are keyed under
  # `Mehungry.Food` and RecipePutNutrientsWorker invalidates with that same
  # key, so the namespace must stay `Mehungry.Food` — not `__MODULE__`.
  @cache_key_ns Mehungry.Food

  def get_recipe_no_caching!(id) do
    {id, _} =
      if(is_integer(id)) do
        {id, nil}
      else
        Integer.parse(id)
      end

    Repo.get(Recipe, id)
    |> Repo.preload([
      [recipe_ingredients: [:measurement_unit, :ingredient, :ingredient_portion]],
      :user,
      recipe_hashtags: [:hashtag],
      comments: [:user, votes: [:user], comment_answers: [:user, votes: [:user]]]
    ])
  end

  def get_recipe!(id) do
    if is_nil(id) do
      nil
    else
      {id, _} =
        if(is_integer(id)) do
          {id, nil}
        else
          Integer.parse(id)
        end

      result =
        case Cachex.get(:recipes_cache, {@cache_key_ns, id}) do
          {:ok, nil} ->
            Logger.warning("Getting recipe " <> Integer.to_string(id) <> " from Database")

            recipe =
              Repo.get(Recipe, id)
              |> Repo.preload([
                [recipe_ingredients: [:measurement_unit, :ingredient, :ingredient_portion]],
                :user,
                [recipe_hashtags: :hashtag]
              ])

            if(not is_nil(recipe)) do
              Cachex.put(:recipes_cache, {@cache_key_ns, recipe.id}, recipe)
              recipe
            end

          {:ok, %Recipe{} = recipe} ->
            Logger.info("Getting recipe " <> Integer.to_string(id) <> " from Cache")

            recipe
        end

      if is_nil(result) do
        result
      else
        Localization.translate_recipe_if_needed(result)
      end
    end
  end

  # Localize a single recipe to `language_name` (a content locale, e.g. "el").
  # Two independent overlays:
  #   * recipe-level — title/description/steps from a `RecipeTranslation`, applied
  #     only when one exists for the locale;
  #   * ingredient-level — ingredient/category/unit names, applied to EVERY
  #     ingredient that has a translation (decoupled from the recipe-level
  #     translation so recipes that were never fully translated still get Greek
  #     ingredient names). Non-dropping: untranslated names fall back to English.
  def get_recipe!(id, language_name) do
    recipe = get_recipe!(id)

    if recipe && language_name do
      translation =
        Map.get(Localization.load_recipe_translations_map([recipe.id], language_name), recipe.id)

      recipe
      |> Localization.apply_recipe_translation(translation)
      |> Localization.localize_recipe_ingredients(language_name)
    else
      recipe
    end
  end

  def delete_recipe(id) do
    Repo.get!(Recipe, id)
    |> delete_recipe_record()
  end

  @doc """
  Deletes a recipe only when it belongs to `user`. Owner-scoped so a forged id
  in a LiveView event can't delete another user's recipe (mirrors
  `delete_user_ingredient`/`delete-meal-plan`). Returns `{:error, :not_found}`
  when the recipe is missing or not owned by the user.
  """
  def delete_user_recipe(%{id: user_id}, id) do
    case Repo.get_by(Recipe, id: id, user_id: user_id) do
      nil -> {:error, :not_found}
      recipe -> delete_recipe_record(recipe)
    end
  end

  defp delete_recipe_record(%Recipe{} = recipe) do
    recipe = Repo.preload(recipe, [:recipe_ingredients])
    id = recipe.id

    result =
      Repo.transaction(fn ->
        # Tables whose FK to recipes is on_delete: :nothing/:restrict (unlike the
        # cascading ones) — a recipe referenced by any of them raises
        # Ecto.ConstraintError on Repo.delete and is left undeletable (the
        # symptom: recipes that have been added to a calendar/meal plan, liked,
        # rated, or annotated won't delete). They all die with the recipe, so
        # clear them first.
        Repo.delete_all(from(r in "ratings", where: r.recipe_id == ^id))
        Repo.delete_all(from(r in "likes", where: r.recipe_id == ^id))
        Repo.delete_all(from(r in "meals", where: r.recipe_id == ^id))
        Repo.delete_all(from(r in "annotations", where: r.recipe_id == ^id))
        Repo.delete_all(from(r in "ai_bot_recipes", where: r.recipe_id == ^id))

        # Basket items are a user's shopping-list entries, not part of the
        # recipe: keep the item, just drop the now-dangling recipe provenance.
        Repo.update_all(
          from(b in "basket_items", where: b.recipe_id == ^id),
          set: [recipe_id: nil]
        )

        Enum.each(recipe.recipe_ingredients, &Repo.delete!/1)

        Repo.delete!(recipe)
      end)

    # Object-storage delete is network I/O — do it after the DB transaction
    # commits so we don't hold a connection open across the HTTP call.
    with {:ok, _} <- result do
      Mehungry.Storage.delete_by_url(recipe.image_url)
    end

    result
  end

  @doc """
  Ecto query selecting the ids of recipes that have zero linked ingredients
  (no `RecipeIngredient` rows). Shared by the count/list/delete helpers below so
  they all agree on what "empty" means.
  """
  def recipe_ids_without_ingredients_query do
    with_ingredients =
      from(ri in Mehungry.Food.RecipeIngredient, select: ri.recipe_id, distinct: true)

    from(r in Recipe, where: r.id not in subquery(with_ingredients), select: r.id)
  end

  @doc "Number of recipes that have no linked ingredients."
  def count_recipes_without_ingredients do
    from(r in Recipe, where: r.id in subquery(recipe_ids_without_ingredients_query()))
    |> Repo.aggregate(:count)
  end

  @doc """
  Up to `:limit` (default 3) public recipes that carry a non-empty `nutrients`
  map, in random order — the landing page's meal-planning demo chart needs
  nutrients, not images. Optionally scoped to a single author via `:user_id`.
  """
  def list_recipes_with_nutrients(opts \\ []) do
    limit = Keyword.get(opts, :limit, 3)

    query =
      from(r in Recipe,
        where: (is_nil(r.private) or not r.private) and fragment("? <> '{}'::jsonb", r.nutrients),
        order_by: fragment("RANDOM()"),
        limit: ^limit
      )

    query =
      case Keyword.fetch(opts, :user_id) do
        {:ok, user_id} -> from(r in query, where: r.user_id == ^user_id)
        :error -> query
      end

    Repo.all(query)
  end

  @doc "Lists recipes with no linked ingredients (for admin preview)."
  def list_recipes_without_ingredients do
    from(r in Recipe,
      where: r.id in subquery(recipe_ids_without_ingredients_query()),
      order_by: [desc: r.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload(:user)
  end

  @doc """
  Searches recipes for the admin recipes tab. A blank `term` returns the most
  recent recipes; otherwise matches `title` case-insensitively. Also accepts a
  bare integer id. Preloads the owner and annotates each row with an
  `ingredient_count` so the admin can see what a delete would take with it.
  Capped at `limit` (default 50) rows.
  """
  def search_recipes_for_admin(term, limit \\ 50) when is_binary(term) do
    term = String.trim(term)

    base =
      from(r in Recipe,
        order_by: [desc: r.inserted_at],
        limit: ^limit
      )

    query =
      case {term, Integer.parse(term)} do
        {"", _} ->
          base

        {_, {id, ""}} ->
          from(r in base, where: r.id == ^id or ilike(r.title, ^"%#{term}%"))

        _ ->
          from(r in base, where: ilike(r.title, ^"%#{term}%"))
      end

    recipes = query |> Repo.all() |> Repo.preload(:user)

    counts =
      from(ri in Mehungry.Food.RecipeIngredient,
        where: ri.recipe_id in ^Enum.map(recipes, & &1.id),
        group_by: ri.recipe_id,
        select: {ri.recipe_id, count(ri.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.map(recipes, fn r -> Map.put(r, :ingredient_count, Map.get(counts, r.id, 0)) end)
  end

  @doc """
  Deletes every recipe that has zero linked ingredients along with all of its
  dependent rows, in a single transaction. Mirrors the cascade in
  `Ingredients.delete_ingredients_without_nutrients/0` so foreign-key
  constraints are satisfied. Returns `{:ok, deleted_count}`.
  """
  def delete_recipes_without_ingredients do
    recipe_ids_q = recipe_ids_without_ingredients_query()

    comment_ids_q =
      from(c in Mehungry.Posts.Comment,
        where: c.recipe_id in subquery(recipe_ids_q),
        select: c.id
      )

    comment_answer_ids_q =
      from(ca in Mehungry.Posts.CommentAnswer,
        where: ca.comment_id in subquery(comment_ids_q),
        select: ca.id
      )

    post_ids_q =
      from(p in Mehungry.Posts.Post, where: p.recipe_id in subquery(recipe_ids_q), select: p.id)

    Repo.transaction(fn ->
      from(cav in Mehungry.Posts.CommentAnswerVote,
        where: cav.comment_answer_id in subquery(comment_answer_ids_q)
      )
      |> Repo.delete_all()

      from(cv in Mehungry.Posts.CommentVote, where: cv.comment_id in subquery(comment_ids_q))
      |> Repo.delete_all()

      from(ca in Mehungry.Posts.CommentAnswer, where: ca.comment_id in subquery(comment_ids_q))
      |> Repo.delete_all()

      from(pv in Mehungry.Posts.PostUpvote, where: pv.post_id in subquery(post_ids_q))
      |> Repo.delete_all()

      from(pv in Mehungry.Posts.PostDownvote, where: pv.post_id in subquery(post_ids_q))
      |> Repo.delete_all()

      from(c in Mehungry.Posts.Comment, where: c.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(p in Mehungry.Posts.Post, where: p.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(l in Mehungry.Food.Like, where: l.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(r in "ratings", where: r.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(ur in Mehungry.Accounts.UserRecipe, where: ur.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(m in Mehungry.Plans.Meal, where: m.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(bi in Mehungry.Inventory.BasketItem, where: bi.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(a in Mehungry.Food.Annotation, where: a.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(rh in Mehungry.Food.RecipeHashtag, where: rh.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(ab in Mehungry.AI.Bot.AiBotRecipe, where: ab.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      {recipe_count, _} =
        from(r in Recipe, where: r.id in subquery(recipe_ids_q))
        |> Repo.delete_all()

      recipe_count
    end)
  end

  @doc """
  Deletes the given recipes and **all** of their dependent rows in one
  transaction. Unlike `delete_recipes_without_ingredients/0`, this also removes
  `recipe_ingredients` (and `recipe_posts`/`recipe_translations`/
  `history_recipe_user_meals`), so it is safe for recipes that still have
  ingredients — used when a recipe is collateral of a junk measurement-unit
  purge (see `Mehungry.Food.Measurements.purge_junk_measurement_unit/1`).
  Returns `{:ok, deleted_recipe_count}`.
  """
  def delete_recipes_by_ids([]), do: {:ok, 0}

  def delete_recipes_by_ids(recipe_ids) when is_list(recipe_ids) do
    comment_ids =
      from(c in Mehungry.Posts.Comment, where: c.recipe_id in ^recipe_ids, select: c.id)
      |> Repo.all()

    comment_answer_ids =
      from(ca in Mehungry.Posts.CommentAnswer,
        where: ca.comment_id in ^comment_ids,
        select: ca.id
      )
      |> Repo.all()

    post_ids =
      from(p in Mehungry.Posts.Post, where: p.recipe_id in ^recipe_ids, select: p.id)
      |> Repo.all()

    Repo.transaction(fn ->
      from(cav in Mehungry.Posts.CommentAnswerVote,
        where: cav.comment_answer_id in ^comment_answer_ids
      )
      |> Repo.delete_all()

      from(cv in Mehungry.Posts.CommentVote, where: cv.comment_id in ^comment_ids)
      |> Repo.delete_all()

      from(ca in Mehungry.Posts.CommentAnswer, where: ca.comment_id in ^comment_ids)
      |> Repo.delete_all()

      from(pv in Mehungry.Posts.PostUpvote, where: pv.post_id in ^post_ids)
      |> Repo.delete_all()

      from(pv in Mehungry.Posts.PostDownvote, where: pv.post_id in ^post_ids)
      |> Repo.delete_all()

      from(c in Mehungry.Posts.Comment, where: c.recipe_id in ^recipe_ids) |> Repo.delete_all()
      from(p in Mehungry.Posts.Post, where: p.recipe_id in ^recipe_ids) |> Repo.delete_all()
      from(l in Mehungry.Food.Like, where: l.recipe_id in ^recipe_ids) |> Repo.delete_all()
      from(r in "ratings", where: r.recipe_id in ^recipe_ids) |> Repo.delete_all()

      from(ur in Mehungry.Accounts.UserRecipe, where: ur.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      from(m in Mehungry.Plans.Meal, where: m.recipe_id in ^recipe_ids) |> Repo.delete_all()

      from(bi in Mehungry.Inventory.BasketItem, where: bi.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      from(a in Mehungry.Food.Annotation, where: a.recipe_id in ^recipe_ids) |> Repo.delete_all()

      from(rh in Mehungry.Food.RecipeHashtag, where: rh.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      from(ab in Mehungry.AI.Bot.AiBotRecipe, where: ab.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      from(ri in Mehungry.Food.RecipeIngredient, where: ri.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      # Schemaless sources for the remaining recipe-referencing tables.
      from(rp in "recipe_posts", where: rp.recipe_id in ^recipe_ids) |> Repo.delete_all()
      from(rt in "recipe_translations", where: rt.recipe_id in ^recipe_ids) |> Repo.delete_all()

      from(hr in "history_recipe_user_meals", where: hr.recipe_id in ^recipe_ids)
      |> Repo.delete_all()

      {recipe_count, _} =
        from(r in Recipe, where: r.id in ^recipe_ids) |> Repo.delete_all()

      recipe_count
    end)
  end

  def change_recipe(recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  def change_step(%Step{} = step, attrs \\ %{}) do
    Step.changeset(step, attrs)
  end

  @doc """
  Returns a `%{user_id => created_recipe_count}` map for every user who has
  created at least one recipe. Used to filter/annotate the admin users listing
  without an N+1 query per user.
  """
  def recipe_counts_by_user_id do
    from(rec in Recipe,
      where: not is_nil(rec.user_id),
      group_by: rec.user_id,
      select: {rec.user_id, count(rec.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def count_user_created_recipes(nil), do: nil

  def count_user_created_recipes(user_id) do
    from(rec in Recipe,
      where: rec.user_id == ^user_id,
      select: count(rec.id)
    )
    |> Repo.one()
  end

  def count_recipes_created_by_user_ids(user_ids) do
    from(rec in Recipe,
      where: rec.user_id in ^user_ids,
      group_by: rec.user_id,
      select: {rec.user_id, count(rec.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def count_recipes do
    Repo.aggregate(Recipe, :count)
  end

  @doc "Counts recipes carrying the given provenance `source` (e.g. \"myplate\")."
  def count_recipes_by_source(source) when is_binary(source) do
    Repo.aggregate(from(r in Recipe, where: r.source == ^source), :count)
  end

  @doc "All recipe ids with the given provenance `source`."
  def recipe_ids_by_source(source) when is_binary(source) do
    Repo.all(from r in Recipe, where: r.source == ^source, select: r.id)
  end

  @doc """
  Group-deletes every recipe with the given provenance `source` (and all their
  references), via `delete_recipes_by_ids/1`. Returns `{:ok, count}`.
  """
  def delete_recipes_by_source(source) when is_binary(source) do
    source |> recipe_ids_by_source() |> delete_recipes_by_ids()
  end

  def count_recipes_missing_embeddings do
    Repo.aggregate(from(r in Recipe, where: is_nil(r.embedding)), :count)
  end

  def list_recipe_ids do
    Repo.all(from r in Recipe, select: r.id)
  end

  @doc """
  Query for recipes carrying a given nutrient-claim badge (see
  `Food.NutrientClaims`), e.g. `recipes_with_badge("Iron")` → recipes **high in**
  iron. `level` is `"high"` (default) or `"source"`.

  Returns an `Ecto.Query` so callers can compose further (pagination, ordering,
  preloads). Matches against the persisted `recipes.badges` jsonb array.
  """
  def recipes_with_badge(label, level \\ "high") do
    from r in Recipe,
      where:
        fragment(
          "EXISTS (SELECT 1 FROM unnest(?) AS b WHERE b->>'nutrient' = ? AND b->>'level' = ?)",
          r.badges,
          ^label,
          ^level
        )
  end

  @doc """
  Public, crawlable listing for a nutrient-claim badge — the
  `/search/nutrient/:slug` browse surface. Mirrors
  `IngredientQueries.search_hashtag1/1`: returns `{query, {recipes, cursor_after}}`
  where `query` is the composable badge query (stored in the LiveView for
  load-more) and the second element is the first cursor page.

  Unlike the hashtag/ingredient searches, this **excludes private and image-less
  recipes** — it is an indexable public page, so it must not surface a private
  recipe or a card with no image. `level` defaults to `"high"` (the only tier the
  UI exposes).
  """
  def search_recipes_by_badge(label, level \\ "high", language_name \\ nil) do
    query =
      from r in recipes_with_badge(label, level),
        where: not is_nil(r.image_url) and (is_nil(r.private) or r.private == false)

    {query, list_recipes(query, language_name)}
  end

  def list_user_recipes_for_selection(nil) do
    entries = Repo.all(Recipe)

    results = Repo.preload(entries, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        Localization.translate_recipe_if_needed(rec)
      end)

    result
  end

  def list_user_recipes_for_selection(_user_id) do
    entries = Repo.all(Recipe)
    results = Repo.preload(entries, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        Localization.translate_recipe_if_needed(rec)
      end)

    result
  end

  def list_recipes(%Ecto.Query{} = query), do: list_recipes(query, nil)

  def list_recipes(cursor_after), do: list_recipes(cursor_after, nil, nil)

  def list_recipes(%Ecto.Query{} = query, language_name) do
    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    cursor_after = metadata.after
    results = Repo.preload(entries, [:user, :user_recipes])
    {Localization.localize_recipes(results, language_name), cursor_after}
  end

  def list_recipes(cursor_after, query), do: list_recipes(cursor_after, query, nil)

  def list_recipes(cursor_after, query, language_name) do
    query =
      case query do
        nil -> from recipe in Recipe, where: not is_nil(recipe.image_url)
        _ -> query
      end

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        after: cursor_after,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    cursor_after = metadata.after
    results = Repo.preload(entries, [:user])
    {Localization.localize_recipes(results, language_name), cursor_after}
  end

  @doc """
  Offset-paginated listing for an already-ordered `Recipe` query. Unlike the
  cursor-based `list_recipes/3`, this preserves the query's own `order_by`
  (e.g. a condition-prioritized ordering that can't be expressed as cursor
  fields), returning page `page` (1-based) of `per_page` localized recipes.
  """
  def list_recipes_page(%Ecto.Query{} = query, page, per_page, language_name \\ nil)
      when is_integer(page) and page >= 1 and is_integer(per_page) and per_page >= 1 do
    offset = (page - 1) * per_page

    from(r in query, limit: ^per_page, offset: ^offset)
    |> Repo.all()
    |> Repo.preload([:user])
    |> Localization.localize_recipes(language_name)
  end

  def list_user_recipes(user_id) do
    query = from recipe in Recipe, where: recipe.user_id == ^user_id
    results = Repo.all(query)
    results = Repo.preload(results, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        Localization.translate_recipe_if_needed(rec)
      end)

    result
  end

  @doc """
  Given a candidate list of recipe ids, returns the subset (a `MapSet`) whose
  recipe carries the diet hashtag for `diet_mode` (`:vegan | :vegetarian`) — the
  same `#vegan`/`#vegetarian` tags `DietClassifier` attaches from ingredient
  categories and the browse/home feeds filter on. For any other `diet_mode`
  (e.g. `nil`) returns the input ids unchanged (no diet filter applies).

  Deterministic diet enforcement: a vegan plan draws only from recipes tagged
  vegan, catching category-level foods (chicken, salmon) that the literal
  `avoid_foods` substring filter misses.
  """
  def recipe_ids_with_diet_tag(recipe_ids, diet_mode)
      when diet_mode in [:vegan, :vegetarian] and is_list(recipe_ids) do
    tag = Atom.to_string(diet_mode)

    from(r in Recipe,
      join: rh in assoc(r, :recipe_hashtags),
      join: h in assoc(rh, :hashtag),
      where: r.id in ^recipe_ids and h.title == ^tag,
      select: r.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def recipe_ids_with_diet_tag(recipe_ids, _diet_mode) when is_list(recipe_ids),
    do: MapSet.new(recipe_ids)

  @doc """
  Given a candidate list of recipe ids, returns the subset (a `MapSet`) whose
  recipe carries **every** hashtag title in `titles` (titles without a leading
  `#`, as stored — the same form `recipe_ids_with_diet_tag/2` and the recipe
  description regex use). An empty `titles` list applies no filter and returns
  the input ids unchanged.

  The general preparation-/style-tag gate behind blueprint `required_hashtags`
  (e.g. `["raw"]` for the Raw Vegan / Raw Vegetarian diet patterns), enforced in
  `MealPlanAgent.search_catalog` on top of the vegan/vegetarian diet filter.
  """
  def recipe_ids_with_all_hashtags(recipe_ids, []) when is_list(recipe_ids),
    do: MapSet.new(recipe_ids)

  def recipe_ids_with_all_hashtags(recipe_ids, titles)
      when is_list(recipe_ids) and is_list(titles) do
    needed = length(titles)

    from(r in Recipe,
      join: rh in assoc(r, :recipe_hashtags),
      join: h in assoc(rh, :hashtag),
      where: r.id in ^recipe_ids and h.title in ^titles,
      group_by: r.id,
      having: count(fragment("DISTINCT ?", h.title)) == ^needed,
      select: r.id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  The subset of `recipe_ids` that are **pescatarian-safe**: every ingredient is
  categorized and none falls in a meat/poultry category (fish & seafood allowed,
  per `Categories.diet_category_ids(:pescatarian)`).

  Pescatarian has no precomputed `#pescatarian` hashtag the way vegan/vegetarian
  do (a pescatarian recipe is "vegetarian ∪ fish-only", not a single positive
  tag), so this is computed on the fly over the candidate set — the **inverse**
  of `recipe_ids_with_diet_tag/2`: drop recipes that *contain* an excluded
  category rather than keep ones that carry a tag. Conservative on unknowns like
  `DietClassifier`: a recipe with an uncategorized ingredient (or no ingredients)
  is dropped, since we can't prove it's meat-free.
  """
  def pescatarian_recipe_ids(recipe_ids) when is_list(recipe_ids) do
    excluded = MapSet.new(Categories.diet_category_ids(:pescatarian))

    from(r in Recipe,
      join: ri in assoc(r, :recipe_ingredients),
      join: i in assoc(ri, :ingredient),
      where: r.id in ^recipe_ids,
      select: {r.id, i.category_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {rid, _} -> rid end, fn {_, cat_id} -> cat_id end)
    |> Enum.filter(fn {_rid, cat_ids} ->
      Enum.all?(cat_ids, &(not is_nil(&1))) and
        MapSet.disjoint?(MapSet.new(cat_ids), excluded)
    end)
    |> Enum.map(fn {rid, _} -> rid end)
    |> MapSet.new()
  end

  @doc """
  Builds a recipe changeset with the **full save-time validation** applied: the
  schema `Recipe.changeset/2` plus the ingredient unit/portion check that
  `create_recipe/1` and `update_recipe/2` enforce before writing.

  The create-recipe form runs this on every `validate` so its "ready to save"
  indicator reflects what saving actually requires — the portion check is
  otherwise invisible until the user presses Save. DB-only constraints (e.g. the
  unique title) still surface only at insert/update time.
  """
  def validation_changeset(recipe, attrs) do
    recipe
    |> Recipe.changeset(attrs)
    |> validate_ingredient_units_in_changeset()
  end

  def create_recipe(attrs \\ %{}) do
    recipe_hashtags = get_recipe_hashtags(attrs)
    attrs = Mehungry.Utils.put_map(attrs, :recipe_hashtags, recipe_hashtags)

    changeset =
      validation_changeset(%Recipe{}, attrs)
      |> validate_title_unique()

    result =
      if changeset.valid? do
        Repo.insert(changeset)
      else
        Logger.warning("Trying to save with errors #{inspect(changeset.errors)} ")
        {:error, changeset}
      end

    case result do
      {:ok, %Recipe{} = recipe} ->
        # Reconcile hashtags on every create path (manual, AI, bot): reconnect
        # the description's #tags and auto-attach #vegan/#vegetarian when the
        # recipe qualifies. Additive and idempotent — see ensure_recipe_hashtags/1.
        ensure_recipe_hashtags(recipe.id)

        %{recipe_id: recipe.id}
        |> Mehungry.RecipePutNutrientsWorker.new()
        |> Oban.insert()

        # Accept either key form: form/AI callers pass string keys, the
        # Spoonacular importer builds atom-keyed attrs. A string-only lookup
        # missed an imported image_url and queued a needless AI cover image.
        if (attrs["image_url"] || attrs[:image_url]) in [nil, ""] do
          %{recipe_id: recipe.id}
          |> Mehungry.RecipeImageWorker.new()
          |> Oban.insert()
        end

        Mehungry.ObanWorkers.RecipeEmbeddingWorker.enqueue(recipe.id)

        result

      _ ->
        result
    end
  end

  def update_recipe(%Recipe{} = recipe_origin, attrs \\ %{}) do
    recipe_hashtags = get_recipe_hashtags(attrs)

    attrs = Mehungry.Utils.put_map(attrs, :recipe_hashtags, recipe_hashtags)

    changeset =
      validation_changeset(recipe_origin, attrs)
      |> validate_title_unique()

    result =
      if changeset.valid? do
        Repo.update(changeset)
      else
        {:error, changeset}
      end

    case result do
      {:ok, %Recipe{} = recipe} ->
        # Reconcile hashtags after the update lands: reconnect description #tags
        # and refresh #vegan/#vegetarian (additive) — see ensure_recipe_hashtags/1.
        ensure_recipe_hashtags(recipe.id)

        %{
          recipe_id: recipe.id
        }
        |> Mehungry.RecipePutNutrientsWorker.new()
        |> Oban.insert()

        Mehungry.ObanWorkers.RecipeEmbeddingWorker.enqueue(recipe.id)
        # Drop the cache entry rather than caching the just-updated struct: the
        # reconcile above may have attached new hashtag rows not on `recipe`, so
        # let the next read reload the full, current recipe.
        Cachex.del(:recipes_cache, {@cache_key_ns, recipe.id})

        case Map.get(attrs, "image_url") do
          nil ->
            result

          _image_url ->
            %{
              recipe_id: recipe.id,
              origin_url: recipe_origin.image_url,
              new_url: recipe.image_url
            }
            |> Mehungry.RecipeCreationWorker.new()
            |> Oban.insert()

            result
        end

      {:error, changeset} ->
        Logger.warning("Trying to save with errors #{inspect(changeset.errors)} ")
        result
    end
  end

  def create_post_from_recipe(%Recipe{} = recipe) do
    Mehungry.Posts.create_post(recipe)
  end

  def put_nutrient_info(%Ecto.Changeset{valid?: true} = changeset, attrs) do
    start = System.monotonic_time()

    {primary_size, nutrients, coverage} =
      Mehungry.Food.NutrientCalculation.calculate_recipe_nutrition_value_with_coverage(attrs)

    if Enum.empty?(nutrients) do
      duration =
        (System.monotonic_time() - start) |> System.convert_time_unit(:native, :millisecond)

      Logger.warning("nutrition calculation(empty): #{duration}ms for recipe")

      # Clear any stale claims — a recipe that lost its nutrition can't keep a
      # "High in Iron" badge.
      Ecto.Changeset.put_change(changeset, :badges, [])
    else
      nutrients =
        nutrients
        |> Enum.map(fn x -> Map.new([{x.name, x}]) end)
        |> Enum.reduce(&Map.merge/2)

      duration =
        (System.monotonic_time() - start)
        |> System.convert_time_unit(:native, :millisecond)

      Logger.warning("nutrition calculation: #{duration}ms for recipe")

      changeset
      |> Ecto.Changeset.put_change(:nutrients, nutrients)
      |> Ecto.Changeset.put_change(:primary_nutrients_size, primary_size)
      |> Ecto.Changeset.put_change(:badges, compute_badges(nutrients, attrs, coverage))
    end
  end

  # Per-serving nutrient-claim badges (see Food.NutrientClaims). `nutrients` here
  # is the freshly-built **atom-keyed** tree; NutrientClaims/`find_nutrient` read
  # the **string-keyed** JSONB shape, so round-trip through JSON first — this is
  # exactly what Ecto persists and reloads, so stored badges match a derive-on-
  # read of the same recipe. `coverage` is the recipe's mass-weighted
  # nutrient-data coverage ratio; NutrientClaims suppresses all badges below its
  # floor so a recipe built mostly from data-less ingredients can't over-claim.
  defp compute_badges(nutrients, attrs, coverage) do
    servings = Map.get(attrs, :servings) || Map.get(attrs, "servings")

    nutrients
    |> Jason.encode!()
    |> Jason.decode!()
    |> NutrientClaims.badges_for_storage(servings, coverage: coverage)
  end

  # Checks that every new/modified recipe ingredient has a resolvable
  # unit-to-gram mapping and adds a user-visible changeset error for each
  # missing IngredientPortion.  Called in both create_recipe and update_recipe
  # so the user receives the error immediately rather than silently getting
  # wrong nutrition values later.
  # Application-level uniqueness for a user's recipe titles. The DB `title_user_index`
  # is not created (see the create_recipes migration), so the schema's
  # `unique_constraint` never fires; this query-based check enforces it at save
  # time with a friendly, field-level message. Excludes the recipe itself on update.
  # (Small race window under concurrent submits — acceptable for this surface.)
  defp validate_title_unique(changeset) do
    user_id = Ecto.Changeset.get_field(changeset, :user_id)
    title = Ecto.Changeset.get_field(changeset, :title)
    current_id = Ecto.Changeset.get_field(changeset, :id)

    if is_nil(user_id) or is_nil(title) or title == "" do
      changeset
    else
      query = from(r in Recipe, where: r.user_id == ^user_id and r.title == ^title)
      query = if current_id, do: from(r in query, where: r.id != ^current_id), else: query

      if Repo.exists?(query) do
        Ecto.Changeset.add_error(
          changeset,
          :title,
          "you already have a recipe with this title"
        )
      else
        changeset
      end
    end
  end

  defp validate_ingredient_units_in_changeset(changeset) do
    ri_changesets = Ecto.Changeset.get_change(changeset, :recipe_ingredients) || []

    ingredient_params =
      ri_changesets
      |> Enum.reject(fn cs -> cs.action == :delete end)
      # Only validate rows the user actually touched: brand-new rows, or existing
      # rows whose unit/ingredient selection changed. Legacy rows are re-submitted
      # unchanged by the edit form and may predate their IngredientPortion (see
      # Mehungry.ReconcileRecipeIngredientPortions) — flagging those would make an
      # old recipe unsaveable even when the edit doesn't touch the offending row.
      |> Enum.filter(&unit_selection_touched?/1)
      |> Enum.map(fn cs ->
        %{
          ingredient_id: Ecto.Changeset.get_field(cs, :ingredient_id),
          measurement_unit_id: Ecto.Changeset.get_field(cs, :measurement_unit_id)
        }
      end)
      |> Enum.reject(fn p -> is_nil(p.ingredient_id) or is_nil(p.measurement_unit_id) end)

    case Mehungry.Food.NutrientCalculation.validate_ingredient_units(ingredient_params) do
      :ok ->
        changeset

      {:error, missing} ->
        Enum.reduce(missing, changeset, fn %{ingredient_name: name, unit_name: unit}, cs ->
          Ecto.Changeset.add_error(
            cs,
            :recipe_ingredients,
            "Ingredient '#{name}' has no portion defined for unit '#{unit}'. " <>
              "Add it in the ingredient editor or choose a different unit."
          )
        end)
    end
  end

  # A row is worth validating when it is new (no persisted id) or when this save
  # actually changes what unit/ingredient it resolves to. `unit_selection` is the
  # form's picker; `measurement_unit_id`/`ingredient_portion_id`/`ingredient_id`
  # cover non-form callers.
  defp unit_selection_touched?(%Ecto.Changeset{data: %{id: nil}}), do: true

  defp unit_selection_touched?(%Ecto.Changeset{} = cs) do
    Enum.any?(
      [:unit_selection, :measurement_unit_id, :ingredient_portion_id, :ingredient_id],
      &Map.has_key?(cs.changes, &1)
    )
  end

  defp get_recipe_hashtags(attrs) do
    case is_nil(attrs["description"]) do
      true ->
        case is_nil(attrs[:description]) do
          true ->
            []

          false ->
            get_hashtags_string(attrs[:description])
        end

      false ->
        get_hashtags_string(attrs["description"])
    end
  end

  # Match a `#` followed by one or more letters/numbers/underscore/hyphen. This
  # keeps surrounding punctuation (`#vegan,`, `(#dinner)`) and any whitespace from
  # ending up in the tag title, and is Unicode-aware so non-Latin tags (Greek,
  # etc.) survive. A bare `#` with no word chars matches nothing.
  @hashtag_regex ~r/#([\p{L}\p{N}_-]+)/u

  defp get_hashtags_string(the_string) do
    @hashtag_regex
    |> Regex.scan(the_string, capture: :all_but_first)
    |> Enum.map(fn [title] -> title end)
    |> Enum.uniq()
    |> Enum.map(fn title ->
      case Mehungry.Hashtag.get_hashtag_by_title(title) do
        nil -> %{hashtag: %{title: title}}
        existing -> %{"hashtag_id" => existing.id}
      end
    end)
  end

  @doc """
  Ensures a recipe is connected to every hashtag it should have. This is the one
  shared reconciliation routine behind manual/AI/bot creation and the admin
  reconciliation sweep, so those paths can never diverge.

  It is **additive and idempotent**: it computes the desired title set as the
  union of

    * the `#tags` parsed out of the recipe's `description` (reconnect), and
    * the diet tags `Mehungry.Food.DietClassifier` derives from the recipe's
      ingredient categories (`#vegan`/`#vegetarian`),

  then get-or-creates each desired `Hashtag` and inserts a `RecipeHashtag` join
  row for any title not already linked. It never deletes join rows or hashtags —
  stale tags are left to be reclaimed (deleting a recipe leaves its hashtags
  alone). Returns `{:ok, added_count}`, or `{:error, :not_found}` if the recipe
  is gone.

  Accepts a `%Recipe{}` or an id.
  """
  def ensure_recipe_hashtags(%Recipe{id: id}), do: ensure_recipe_hashtags(id)

  def ensure_recipe_hashtags(recipe_id) do
    case Repo.get(Recipe, recipe_id) do
      nil ->
        {:error, :not_found}

      recipe ->
        recipe
        |> Repo.preload(recipe_hashtags: [:hashtag], recipe_ingredients: [ingredient: :category])
        |> reconcile_hashtags()
    end
  end

  defp reconcile_hashtags(recipe) do
    description_titles = parse_hashtag_titles(recipe.description)
    diet_titles = DietClassifier.classify(recipe)
    desired = Enum.uniq(description_titles ++ diet_titles)

    existing =
      recipe.recipe_hashtags
      |> Enum.map(fn rh -> rh.hashtag && rh.hashtag.title end)
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    added =
      desired
      |> Enum.reject(&MapSet.member?(existing, &1))
      |> Enum.count(fn title -> link_hashtag(recipe.id, title) == :ok end)

    {:ok, added}
  end

  # Bare titles parsed out of the description (no DB lookup), same regex/dedup as
  # get_hashtags_string/1 but without the create-or-reuse mapping.
  defp parse_hashtag_titles(nil), do: []

  defp parse_hashtag_titles(description) do
    @hashtag_regex
    |> Regex.scan(description, capture: :all_but_first)
    |> Enum.map(fn [title] -> title end)
    |> Enum.uniq()
  end

  defp link_hashtag(recipe_id, title) do
    hashtag = get_or_create_hashtag(title)

    %RecipeHashtag{}
    |> RecipeHashtag.changeset(%{"recipe_id" => recipe_id, "hashtag_id" => hashtag.id})
    |> Repo.insert()
    |> case do
      {:ok, _} -> :ok
      {:error, _changeset} -> :noop
    end
  end

  defp get_or_create_hashtag(title) do
    case Hashtag.get_hashtag_by_title(title) do
      nil ->
        %Hashtag{}
        |> Hashtag.changeset(%{title: title})
        |> Repo.insert()
        |> case do
          {:ok, hashtag} -> hashtag
          # Lost a race to a concurrent insert — the unique(:title) constraint
          # fired; re-read the row the other writer created.
          {:error, _changeset} -> Hashtag.get_hashtag_by_title(title)
        end

      existing ->
        existing
    end
  end

  # ── Recipe social graphics (insight share cards) ───────────────────────────

  @doc "Persist a generated insight graphic row for a recipe."
  def create_recipe_social_graphic(attrs) do
    %RecipeSocialGraphic{}
    |> RecipeSocialGraphic.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Persist a generated shareable weekly-plan card row for a user."
  def create_weekly_plan_graphic(attrs) do
    %WeeklyPlanGraphic{}
    |> WeeklyPlanGraphic.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  The most recently generated weekly-plan card for a user's week, or `nil`. Lets
  the share UI show the existing card instead of forcing a regenerate.
  """
  def latest_weekly_plan_graphic(user_id, %Date{} = week_start) do
    Repo.one(
      from(g in WeeklyPlanGraphic,
        where: g.user_id == ^user_id and g.week_start == ^week_start,
        order_by: [desc: g.id],
        limit: 1
      )
    )
  end

  @doc "The most recently generated insight graphic for a recipe, or `nil`."
  def latest_recipe_social_graphic(recipe_id) do
    Repo.one(
      from(g in RecipeSocialGraphic,
        where: g.recipe_id == ^recipe_id,
        order_by: [desc: g.id],
        limit: 1
      )
    )
  end

  @doc """
  Returns the recipe with its `image_url` swapped to the newest generated insight
  social-graphic when one exists — so social-media posts surface the branded,
  macro/compound-annotated graphic instead of the plain cover photo. Returns the
  recipe unchanged when it has no generated graphic.
  """
  def recipe_with_share_image(%Recipe{} = recipe) do
    case latest_recipe_social_graphic(recipe.id) do
      %RecipeSocialGraphic{image_url: url} when is_binary(url) and url != "" ->
        %{recipe | image_url: url}

      _ ->
        recipe
    end
  end
end
