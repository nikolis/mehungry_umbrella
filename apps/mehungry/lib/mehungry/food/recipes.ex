defmodule Mehungry.Food.Recipes do
  @moduledoc """
  Recipe CRUD, listing/pagination, per-user recipe queries and counts,
  nutrition enrichment on save, and the recipes cache.
  """

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo
  alias Mehungry.Food.{Localization, Recipe, Step}

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
                :recipe_hashtags
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

  def get_recipe!(id, language_name) do
    recipe = get_recipe!(id)

    if recipe && language_name do
      translation =
        Map.get(Localization.load_recipe_translations_map([recipe.id], language_name), recipe.id)

      ing_lang = Localization.ingredient_language_for(language_name)

      if translation && ing_lang do
        recipe
        |> Localization.apply_recipe_translation(translation)
        |> Localization.translate_ingredients_to(ing_lang)
      else
        Localization.apply_recipe_translation(recipe, translation)
      end
    else
      recipe
    end
  end

  def delete_recipe(id) do
    recipe =
      Repo.get!(Recipe, id)
      |> Repo.preload([:recipe_ingredients])

    Enum.each(recipe.recipe_ingredients, fn rec_in ->
      Repo.delete(rec_in)
    end)

    if !is_nil(recipe.image_url) and not String.starts_with?(recipe.image_url, "http") do
      file_name = List.last(String.split(recipe.image_url))

      Mehungry.S3.delete_object("test-bucket-local-mehungry", file_name, region: "eu-central-1")
    end

    Repo.delete(recipe)
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

  def count_recipes_missing_embeddings do
    Repo.aggregate(from(r in Recipe, where: is_nil(r.embedding)), :count)
  end

  def list_recipe_ids do
    Repo.all(from r in Recipe, select: r.id)
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

  def create_recipe(attrs \\ %{}) do
    recipe_hashtags = get_recipe_hashtags(attrs)
    attrs = Mehungry.Utils.put_map(attrs, :recipe_hashtags, recipe_hashtags)

    changeset =
      %Recipe{}
      |> Recipe.changeset(attrs)
      |> validate_ingredient_units_in_changeset()

    result =
      if changeset.valid? do
        Repo.insert(changeset)
      else
        Logger.warning("Trying to save with errors #{inspect(changeset.errors)} ")
        {:error, changeset}
      end

    case result do
      {:ok, %Recipe{} = recipe} ->
        %{recipe_id: recipe.id}
        |> Mehungry.RecipePutNutrientsWorker.new()
        |> Oban.insert()

        if attrs["image_url"] in [nil, ""] do
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
      recipe_origin
      |> Recipe.changeset(attrs)
      |> validate_ingredient_units_in_changeset()

    result =
      if changeset.valid? do
        Repo.update(changeset)
      else
        {:error, changeset}
      end

    case result do
      {:ok, %Recipe{} = recipe} ->
        %{
          recipe_id: recipe.id
        }
        |> Mehungry.RecipePutNutrientsWorker.new()
        |> Oban.insert()

        Mehungry.ObanWorkers.RecipeEmbeddingWorker.enqueue(recipe.id)
        Cachex.put(:recipes_cache, {@cache_key_ns, recipe.id}, recipe)

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

    {primary_size, nutrients} =
      Mehungry.Food.NutrientCalculation.calculate_recipe_nutrition_value(attrs)

    if Enum.empty?(nutrients) do
      duration =
        (System.monotonic_time() - start) |> System.convert_time_unit(:native, :millisecond)

      Logger.warning("nutrition calculation(empty): #{duration}ms for recipe")

      changeset
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
    end
  end

  # Checks that every new/modified recipe ingredient has a resolvable
  # unit-to-gram mapping and adds a user-visible changeset error for each
  # missing IngredientPortion.  Called in both create_recipe and update_recipe
  # so the user receives the error immediately rather than silently getting
  # wrong nutrition values later.
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

  defp get_hashtags_string(the_string) do
    terms = String.split(the_string, " ")

    hashtags =
      Enum.filter(terms, fn x ->
        case String.at(x, 0) == "#" do
          true ->
            true

          false ->
            false
        end
      end)

    Enum.map(hashtags, fn x ->
      title = String.slice(x, 1..-1//1)

      case Mehungry.Hashtag.get_hashtag_by_title(title) do
        nil -> %{hashtag: %{title: title}}
        existing -> %{"hashtag_id" => existing.id}
      end
    end)
  end
end
