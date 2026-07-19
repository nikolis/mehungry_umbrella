defmodule Mehungry.Food.Ingredients do
  @moduledoc """
  Ingredient CRUD, lookups (by id/name/slug/translation), portions,
  ingredient nutrients, paginated listings, and recipe-ingredient helpers.
  """

  import Ecto.Query, warn: false

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
end
