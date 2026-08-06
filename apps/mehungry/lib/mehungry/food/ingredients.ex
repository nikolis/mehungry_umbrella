defmodule Mehungry.Food.Ingredients do
  @moduledoc """
  Ingredient CRUD, lookups (by id/name/slug/translation), portions,
  ingredient nutrients, paginated listings, and recipe-ingredient helpers.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Ingredient,
    IngredientNutrient,
    IngredientPortion,
    IngredientTranslation,
    Localization,
    Recipe,
    RecipeIngredient
  }

  def create_ingredient_portion(attrs) do
    %IngredientPortion{}
    |> IngredientPortion.changeset(attrs)
    |> Repo.insert()
  end

  def broadcast_ingredient_work_item(file_url) do
    Phoenix.PubSub.broadcast(Mehungry.PubSub, "json_jobs", %{new_comment_vote: file_url})

    {:ok, :submitted}
  end

  def create_ingredient_nutrient(attrs) do
    %IngredientNutrient{}
    |> IngredientNutrient.changeset(attrs)
    |> Repo.insert()
  end

  def get_ingredient_by_name(name) do
    Repo.get_by(Ingredient, name: name)
  end

  def create_ingredient(attrs) do
    Ingredient.changeset(%Ingredient{}, attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a private, user-owned ingredient. Forces `user_id` (and a
  `"User created"` `food_class` marker unless one is supplied) so the row is
  scoped to its creator and only surfaces in that user's searches.
  """
  def create_user_ingredient(%{id: user_id}, attrs) do
    attrs =
      attrs
      |> put_attr(:user_id, user_id)
      |> maybe_put_food_class()

    create_ingredient(attrs)
  end

  @doc """
  Lists the private ingredients owned by `user`, newest first, with nutrients
  and portions preloaded for display.
  """
  def list_user_ingredients(%{id: user_id}) do
    from(i in Ingredient,
      where: i.user_id == ^user_id,
      order_by: [desc: i.inserted_at]
    )
    |> Repo.all()
    |> Repo.preload([
      [ingredient_nutrients: :nutrient],
      :ingredient_portions,
      :ingredient_translation
    ])
  end

  @doc """
  Fetches one of `user`'s own ingredients by id (raises if it doesn't exist or
  isn't owned by `user`). Use for the edit/update/delete authorization boundary.
  """
  def get_user_ingredient!(%{id: user_id}, id) do
    from(i in Ingredient, where: i.id == ^id and i.user_id == ^user_id)
    |> Repo.one!()
    |> Repo.preload([
      [ingredient_nutrients: :nutrient],
      :ingredient_portions,
      :ingredient_translation
    ])
  end

  # Sets attrs[key] regardless of whether the map uses atom or string keys.
  defp put_attr(attrs, key, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1) do
      Map.put(attrs, Atom.to_string(key), value)
    else
      Map.put(attrs, key, value)
    end
  end

  defp maybe_put_food_class(attrs) do
    cond do
      Map.get(attrs, :food_class) not in [nil, ""] -> attrs
      Map.get(attrs, "food_class") not in [nil, ""] -> attrs
      true -> put_attr(attrs, :food_class, "User created")
    end
  end

  def delete_ingredient(%Ingredient{} = ingredient) do
    Repo.delete(ingredient)
  end

  def delete_ingredients_without_nutrients do
    ids_with_nutrients =
      from(n in IngredientNutrient, select: n.ingredient_id, distinct: true)

    ingredient_ids_q =
      from(i in Ingredient, where: i.id not in subquery(ids_with_nutrients), select: i.id)

    recipe_ids_q =
      from(ri in RecipeIngredient,
        where: ri.ingredient_id in subquery(ingredient_ids_q),
        select: ri.recipe_id,
        distinct: true
      )

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

      from(l in Mehungry.Food.Like, where: l.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(r in "ratings", where: r.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(m in Mehungry.Plans.Meal, where: m.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(bi in Mehungry.Inventory.BasketItem, where: bi.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(a in Mehungry.Food.Annotation, where: a.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(ab in Mehungry.AI.Bot.AiBotRecipe, where: ab.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(ri in RecipeIngredient, where: ri.recipe_id in subquery(recipe_ids_q))
      |> Repo.delete_all()

      from(bi in Mehungry.Inventory.BasketIngredient,
        where: bi.ingredient_id in subquery(ingredient_ids_q)
      )
      |> Repo.delete_all()

      from(uir in Mehungry.Accounts.UserIngredientRule,
        where: uir.ingredient_id in subquery(ingredient_ids_q)
      )
      |> Repo.delete_all()

      from(hium in Mehungry.History.IngredientUserMeal,
        where: hium.ingredient_id in subquery(ingredient_ids_q)
      )
      |> Repo.delete_all()

      from(ip in IngredientPortion, where: ip.ingredient_id in subquery(ingredient_ids_q))
      |> Repo.delete_all()

      {recipe_count, _} =
        from(r in Recipe, where: r.id in subquery(recipe_ids_q))
        |> Repo.delete_all()

      {ingredient_count, _} =
        from(i in Ingredient, where: i.id not in subquery(ids_with_nutrients))
        |> Repo.delete_all()

      {ingredient_count, recipe_count}
    end)
  end

  @doc "PubSub topic carrying `{:branded_delete, payload}` progress updates."
  def branded_delete_topic, do: "branded_ingredient_delete"

  @doc """
  Broadcasts a branded-delete progress update to `branded_delete_topic/0`.
  `payload` is one of `:started`, `{:completed, {ingredient_count, recipe_count}}`,
  or `{:failed, reason}`.
  """
  def broadcast_branded_delete(payload) do
    Phoenix.PubSub.broadcast(
      Mehungry.PubSub,
      branded_delete_topic(),
      {:branded_delete, payload}
    )
  end

  @doc """
  Deletes every USDA "Branded" ingredient (`food_class == "Branded"` or
  `data_type == "Branded"`) and all of its dependent rows. Mirrors the cascade in
  `delete_ingredients_without_nutrients/0` so foreign-key constraints are
  satisfied, including any recipes that reference a branded ingredient. Returns
  `{:ok, {ingredient_count, recipe_count}}`.

  This is a heavy, long-running bulk delete — run it from
  `Mehungry.ObanWorkers.BrandedIngredientDeleteWorker`, never inline in a request.
  """
  def delete_branded_ingredients do
    # Preflight diagnostics: the deployed DB may store the "Branded" marker under
    # a different column/casing than we expect, which would make the delete a
    # silent no-op. Log what actually matches before we touch anything.
    branded_by_food_class =
      Repo.aggregate(from(i in Ingredient, where: i.food_class == "Branded"), :count)

    branded_by_data_type =
      Repo.aggregate(from(i in Ingredient, where: i.data_type == "Branded"), :count)

    distinct_food_classes =
      Repo.all(from(i in Ingredient, select: i.food_class, distinct: true))

    Logger.info(
      "[delete_branded] preflight: food_class=='Branded' -> #{branded_by_food_class}, " <>
        "data_type=='Branded' -> #{branded_by_data_type}, " <>
        "distinct food_class values: #{inspect(distinct_food_classes)}"
    )

    ingredient_ids_q =
      from(i in Ingredient,
        where: i.food_class == "Branded" or i.data_type == "Branded",
        select: i.id
      )

    recipe_ids_q =
      from(ri in RecipeIngredient,
        where: ri.ingredient_id in subquery(ingredient_ids_q),
        select: ri.recipe_id,
        distinct: true
      )

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

    # This deletes hundreds of thousands of branded ingredients plus millions of
    # dependent nutrient/portion rows, which far exceeds Ecto's default 15s query
    # timeout and any DB `statement_timeout` (Postgres cancels with 57014). Give
    # every statement a long timeout and disable the per-statement timeout for the
    # duration of the transaction.
    tx_timeout = :timer.minutes(30)

    del = fn step, query ->
      {count, _} = Repo.delete_all(query, timeout: tx_timeout)
      Logger.info("[delete_branded] #{step}: deleted #{count} row(s)")
      count
    end

    result =
      Repo.transaction(
        fn ->
          Repo.query!("SET LOCAL statement_timeout = 0")

          del.(
            "comment_answer_votes",
            from(cav in Mehungry.Posts.CommentAnswerVote,
              where: cav.comment_answer_id in subquery(comment_answer_ids_q)
            )
          )

          del.(
            "comment_votes",
            from(cv in Mehungry.Posts.CommentVote,
              where: cv.comment_id in subquery(comment_ids_q)
            )
          )

          del.(
            "comment_answers",
            from(ca in Mehungry.Posts.CommentAnswer,
              where: ca.comment_id in subquery(comment_ids_q)
            )
          )

          del.(
            "post_upvotes",
            from(pv in Mehungry.Posts.PostUpvote, where: pv.post_id in subquery(post_ids_q))
          )

          del.(
            "post_downvotes",
            from(pv in Mehungry.Posts.PostDownvote, where: pv.post_id in subquery(post_ids_q))
          )

          del.(
            "likes",
            from(l in Mehungry.Food.Like, where: l.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "ratings",
            from(r in "ratings", where: r.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "meals",
            from(m in Mehungry.Plans.Meal, where: m.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "basket_items",
            from(bi in Mehungry.Inventory.BasketItem,
              where: bi.recipe_id in subquery(recipe_ids_q)
            )
          )

          del.(
            "annotations",
            from(a in Mehungry.Food.Annotation, where: a.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "ai_bot_recipes",
            from(ab in Mehungry.AI.Bot.AiBotRecipe, where: ab.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "recipe_ingredients",
            from(ri in RecipeIngredient, where: ri.recipe_id in subquery(recipe_ids_q))
          )

          del.(
            "basket_ingredients",
            from(bi in Mehungry.Inventory.BasketIngredient,
              where: bi.ingredient_id in subquery(ingredient_ids_q)
            )
          )

          del.(
            "user_ingredient_rules",
            from(uir in Mehungry.Accounts.UserIngredientRule,
              where: uir.ingredient_id in subquery(ingredient_ids_q)
            )
          )

          del.(
            "ingredient_user_meals",
            from(hium in Mehungry.History.IngredientUserMeal,
              where: hium.ingredient_id in subquery(ingredient_ids_q)
            )
          )

          del.(
            "ingredient_portions",
            from(ip in IngredientPortion, where: ip.ingredient_id in subquery(ingredient_ids_q))
          )

          del.(
            "ingredient_nutrients",
            from(int in IngredientNutrient,
              where: int.ingredient_id in subquery(ingredient_ids_q)
            )
          )

          del.(
            "ingredient_translations",
            from(it in IngredientTranslation,
              where: it.ingredient_id in subquery(ingredient_ids_q)
            )
          )

          recipe_count =
            del.("recipes", from(r in Recipe, where: r.id in subquery(recipe_ids_q)))

          ingredient_count =
            del.(
              "ingredients",
              from(i in Ingredient,
                where: i.food_class == "Branded" or i.data_type == "Branded"
              )
            )

          {ingredient_count, recipe_count}
        end,
        timeout: tx_timeout
      )

    case result do
      {:ok, {ingredient_count, recipe_count}} ->
        Logger.info(
          "[delete_branded] committed: #{ingredient_count} ingredient(s), #{recipe_count} recipe(s)"
        )

      {:error, reason} ->
        Logger.error("[delete_branded] transaction failed/rolled back: #{inspect(reason)}")
    end

    result
  end

  def change_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
    Ingredient.changeset(ingredient, attrs)
  end

  def update_ingredient(%Ingredient{} = ingredient, attrs \\ %{}) do
    ingredient
    |> Ingredient.changeset(attrs)
    |> Repo.update()
  end

  def get_ingredient_by_slug(slug) do
    name = String.replace(slug, "-", " ")

    ingredient =
      Repo.get_by(Ingredient, search_name: name) ||
        get_ingredient_by_translation_name(name)

    case ingredient do
      nil ->
        nil

      ingredient ->
        Repo.preload(ingredient, [
          :category,
          ingredient_portions: [:measurement_unit],
          ingredient_nutrients: [nutrient: [:measurement_unit]]
        ])
    end
  end

  def get_ingredient_by_translation_name(name) do
    result =
      from(t in IngredientTranslation,
        join: i in Ingredient,
        on: i.id == t.ingredient_id,
        where: fragment("lower(?) = lower(?)", t.name, ^name),
        limit: 1,
        select: i
      )
      |> Repo.one()

    result
  end

  def get_ingredient_details!(nil), do: nil

  def get_ingredient_details!(id) do
    Repo.get!(Ingredient, id)
    |> Repo.preload(
      ingredient_portions: [:measurement_unit],
      ingredient_nutrients: [nutrient: [:measurement_unit]]
    )
  end

  def get_ingredient_with_category!(id) do
    Repo.get!(Ingredient, id)
    |> Repo.preload(:category)
  end

  def get_ingredient!(id) do
    Repo.get!(Ingredient, id)
    |> Repo.preload(:ingredient_translation)
  end

  def get_ingredient(id) do
    Repo.get(Ingredient, id)
    |> Repo.preload(:ingredient_translation)
  end

  def find_ri_allias(%{"ingredient_id" => ingredient_id} = rec_in, lang_id) do
    translation = Localization.find_ingredient_translation(lang_id, ingredient_id)

    case translation do
      [] ->
        ingredient = get_ingredient(ingredient_id)
        Map.put(rec_in, "ingredient_allias", ingredient.name)

        """
          match empty list
        """

      _trans ->
        {:ok, tr_name} = Enum.fetch(translation, 0)
        Map.put(rec_in, "ingredient_allias", tr_name)
    end
  end

  def list_ingredients() do
    Repo.all(Ingredient)
    |> Repo.preload([:measurement_unit, :category])
  end

  def list_ingredients_paginated() do
    # return the next 50 posts
    query = from(i in Ingredient)

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

  def list_ingredients_paginated_translated(language_name, cursor_after \\ nil) do
    translated_ids =
      from(t in IngredientTranslation,
        where: t.language_name == ^language_name,
        select: t.ingredient_id
      )

    query = from(i in Ingredient, where: i.id in subquery(translated_ids))

    paginate_opts =
      [cursor_fields: [{:inserted_at, :asc}, {:id, :asc}], limit: 20] ++
        if cursor_after, do: [after: cursor_after], else: []

    %{entries: entries, metadata: metadata} = Repo.paginate(query, paginate_opts)

    {Repo.preload(entries, [:category, :ingredient_translation]), metadata.after}
  end

  def list_ingredients_paginated(%Ecto.Query{} = query) do
    # return the next 50 posts

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    # assign the `after` cursor to a variable
    cursor_after = metadata.after

    results = Repo.preload(entries, [:category])

    {results, cursor_after}
  end

  def list_ingredients_paginated(cursor_after, query \\ nil) do
    # return the next 50 posts
    query =
      case query do
        nil ->
          from(ing in Ingredient)

        _ ->
          query
      end

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        after: cursor_after,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    # assign the `after` cursor to a variable
    cursor_after = metadata.after

    results = Repo.preload(entries, [:category])

    {results, cursor_after}
  end

  def list_recipe_ingredients() do
    Repo.all(RecipeIngredient)
  end

  def change_recipe_ingredient(%RecipeIngredient{} = recipe_ingredient, attrs \\ %{}) do
    RecipeIngredient.changeset(recipe_ingredient, attrs)
  end

  # ── USDA reconciliation ────────────────────────────────────────────────

  @doc """
  Enqueues the batched Oban job that backfills `data_type` from `food_class` and
  bumps each row's `version` (self-re-enqueueing until exhausted).
  """
  def enqueue_ingredient_backfill do
    %{}
    |> Mehungry.ObanWorkers.IngredientReconciliationWorker.new()
    |> Oban.insert()
  end

  @doc """
  Backfill coverage as `%{done: n, total: m}`: `done` is the number of rows that
  have reached the current reconciliation pass's target `version`, `total` the
  full ingredient count. Version-based (not `data_type`-based) so NULL
  `food_class` rows still count as done — see the worker's moduledoc.
  """
  def reconciliation_progress do
    target = Mehungry.ObanWorkers.IngredientReconciliationWorker.target_version()
    done = Repo.aggregate(from(i in Ingredient, where: i.version >= ^target), :count)
    %{done: done, total: Repo.aggregate(Ingredient, :count)}
  end
end
