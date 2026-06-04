defmodule Mehungry.Food do
  @moduledoc false

  import Ecto.Query, warn: false
  require Logger

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Recipe,
    Step,
    RecipeIngredient,
    MeasurementUnit,
    MeasurementUnitTranslation,
    IngredientNutrient,
    Category,
    CategoryTranslation,
    Ingredient,
    Nutrient,
    IngredientTranslation,
    Like,
    IngredientPortion,
    NutrientInteractions,
    NutrientMerger
  }

  alias Mehungry.Food.RecipeHashtag
  alias Mehungry.Languages.Language
  alias Mehungry.Hashtag

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

  def search_hashtag(hashtag) do
    from(hashtag in Mehungry.Hashtag,
      where: hashtag.title == ^hashtag
    )
    |> Repo.one()
    |> Repo.preload(recipe_hashtags: [recipe: [recipe_ingredients: :ingredient]])
  end

  def get_nutrient(id) do
    if not is_nil(id) and id != "" do
      query = from nutr in Nutrient, where: nutr.id == ^id

      Repo.one(query)
      |> Repo.preload(:measurement_unit)
    else
      nil
    end
  end

  def get_nutrient(name, measurment_unit_id) do
    query =
      from nutr in Nutrient,
        where:
          nutr.name == ^name and
            nutr.measurement_unit_id == ^measurment_unit_id

    Repo.one(query)
  end

  def create_nutrient(attrs) do
    %Nutrient{}
    |> Nutrient.changeset(attrs)
    |> Repo.insert()
  end

  def delete_category(%Category{} = category) do
    Repo.delete(category)
  end

  def get_category!(id) do
    Repo.get(Category, id)
  end

  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  def change_step(%Step{} = step, attrs \\ %{}) do
    Step.changeset(step, attrs)
  end

  def get_user_likes(user_id) do
    query =
      from a in Like,
        where: a.user_id == ^user_id

    Repo.all(query)
  end

  def like_recipe(user_id, recipe_id) do
    %Like{recipe_id: recipe_id, user_id: user_id}
    |> Repo.insert()
  end

  def list_annotations(%Recipe{} = recipe) do
    Repo.all(
      from a in Ecto.assoc(recipe, :annotations),
        order_by: [asc: a.at, asc: a.id],
        limit: 500,
        preload: [:user]
    )
  end

  alias Mehungry.Food.FoodRestrictionType

  def list_food_restriction_types() do
    Repo.all(from(a in FoodRestrictionType))
  end

  #  def get_user_by_email(email) do
  #    query =
  #      from usr in User,
  #        join: credential in Credential,
  #        where: ^email == credential.email

  #    Repo.get_by(User, query)
  #  end

  def translate_recipe_if_needed(recipe) do
    language =
      from(lan in Language,
        where: lan.name == ^recipe.language_name
      )
      |> Repo.one()

    case language do
      %{name: "Gr"} ->
        query =
          from rec_ing in RecipeIngredient,
            where: rec_ing.recipe_id == ^recipe.id,
            join: ingredient in Ingredient,
            on: true,
            where: ingredient.id == rec_ing.ingredient_id,
            join: tra in IngredientTranslation,
            on: true,
            where: tra.ingredient_id == ingredient.id,
            join: cat in Category,
            on: true,
            where: cat.id == ingredient.category_id,
            join: cat_trans in CategoryTranslation,
            on: true,
            where: cat_trans.category_id == cat.id and ^language.id == cat_trans.language_name,
            join: mu in MeasurementUnit,
            on: true,
            where: mu.id == rec_ing.measurement_unit_id,
            join: mu_trans in MeasurementUnitTranslation,
            on: true,
            where:
              mu_trans.measurement_unit_id == mu.id and ^language.id == mu_trans.language_name,
            select: %RecipeIngredient{
              quantity: rec_ing.quantity,
              ingredient_allias: rec_ing.ingredient_allias,
              measurement_unit: %MeasurementUnit{id: mu.id, name: mu_trans.name},
              ingredient: %Ingredient{
                name: tra.name,
                id: ingredient.id,
                measurement_unit: %MeasurementUnit{id: mu.id, name: mu_trans.name},
                category: %Category{id: cat.id, name: cat_trans.name}
              }
            }

        result = Repo.all(query)
        ret_rec = %Recipe{recipe | recipe_ingredients: result}
        ret_rec

      _ ->
        recipe
        |> Repo.preload([
          :user,
          {:recipe_ingredients,
           [
             {:measurement_unit, :translation},
             {:ingredient, :category}
           ]}
        ])
    end
  end

  def get_measurement_unit!(nil), do: nil

  def get_measurement_unit!(id) do
    Repo.get(MeasurementUnit, id)
  end

  @doc """
  IngredientPortion represents the portions of ingredients and connects bassically ingredients with measurmenet Units 
  """
  def get_measurement_unit_portions_for_ingredient(ingredient_id)
      when is_binary(ingredient_id) and ingredient_id == "" do
    []
  end

  def get_measurement_unit_portions_for_ingredient(ingredient_id) do
    from(ingp in Mehungry.Food.IngredientPortion, where: ingp.ingredient_id == ^ingredient_id)
    |> Repo.all()
    |> Repo.preload(:measurement_unit)
  end

  def get_measurement_unit_by_name(name) do
    from(mu in MeasurementUnit,
      where: mu.name == ^name or mu.alternate_name == ^name
    )
    |> Repo.all()
  end

  def get_category_by_name(nil) do
    nil
  end

  def get_category_by_name(name) do
    from(cate in Category,
      where: cate.name == ^name
    )
    |> Repo.one()
  end

  def delete_recipe(id) do
    recipe =
      Repo.get!(Recipe, id)
      |> Repo.preload([:recipe_ingredients])

    Enum.each(recipe.recipe_ingredients, fn rec_in ->
      Repo.delete(rec_in)
    end)

    if !is_nil(recipe.image_url) do
      file_name = List.last(String.split(recipe.image_url))

      ExAws.S3.delete_object("test-bucket-local-mehungry", file_name)
      |> ExAws.request(region: "eu-central-1")
    end

    Repo.delete(recipe)
  end

  def get_recipe_comments(recipe_id) do
    from(c in Mehungry.Posts.Comment, where: c.recipe_id == ^recipe_id)
    |> Repo.all()
    |> Repo.preload([:user, :votes, [comment_answers: :user]])
  end

  def get_recipe_no_caching!(id) do
    {id, _} =
      if(is_integer(id)) do
        {id, nil}
      else
        Integer.parse(id)
      end

    Repo.get(Recipe, id)
    |> Repo.preload([
      [recipe_ingredients: [:measurement_unit, :ingredient]],
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
        case Cachex.get(:recipes_cache, {__MODULE__, id}) do
          {:ok, nil} ->
            Logger.warning("Getting recipe " <> Integer.to_string(id) <> " from Database")

            recipe =
              Repo.get(Recipe, id)
              |> Repo.preload([
                [recipe_ingredients: [:measurement_unit, :ingredient]],
                :user,
                :recipe_hashtags
              ])

            if(not is_nil(recipe)) do
              Cachex.put(:recipes_cache, {__MODULE__, recipe.id}, recipe)
              recipe
            end

          {:ok, %Recipe{} = recipe} ->
            Logger.info("Getting recipe " <> Integer.to_string(id) <> " from Cache")

            recipe
        end

      if is_nil(result) do
        result
      else
        translate_recipe_if_needed(result)
      end
    end
  end

  def list_categories() do
    Repo.all(Category)
  end

  def list_recipe_ingredients() do
    Repo.all(RecipeIngredient)
  end

  def create_measurement_unit(attrs) do
    %MeasurementUnit{}
    |> MeasurementUnit.changeset(attrs)
    |> Repo.insert()
  end

  def update_measurement_unit(%MeasurementUnit{} = measurement_unit, attrs \\ %{}) do
    measurement_unit
    |> MeasurementUnit.changeset(attrs)
    |> Repo.update()
  end

  def delete_measurement_unit(%MeasurementUnit{} = measrement_unit) do
    Repo.delete(measrement_unit)
  end

  def change_measurement_unit(measurement_unit, attrs \\ %{}) do
    MeasurementUnit.changeset(measurement_unit, attrs)
  end

  def change_recipe_ingredient(%RecipeIngredient{} = recipe_ingredient, attrs \\ %{}) do
    RecipeIngredient.changeset(recipe_ingredient, attrs)
  end

  def list_measurement_units() do
    Repo.all(MeasurementUnit)
  end

  def change_recipe(recipe, attrs \\ %{}) do
    Recipe.changeset(recipe, attrs)
  end

  def count_user_created_recipes(nil), do: nil

  def count_user_created_recipes(user_id) do
    from(rec in Recipe,
      where: rec.user_id == ^user_id,
      select: count(rec.id)
    )
    |> Repo.one()
  end

  def list_user_recipes_for_selection(nil) do
    entries = Repo.all(Recipe)

    results = Repo.preload(entries, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        translate_recipe_if_needed(rec)
      end)

    result
  end

  def list_user_recipes_for_selection(_user_id) do
    entries = Repo.all(Recipe)
    results = Repo.preload(entries, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        translate_recipe_if_needed(rec)
      end)

    result
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

  def list_recipes(%Ecto.Query{} = query) do
    # return the next 50 posts

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    # assign the `after` cursor to a variable
    cursor_after = metadata.after

    results = Repo.preload(entries, [:user, :user_recipes])

    result =
      Enum.map(results, fn rec ->
        translate_recipe_if_needed(rec)
      end)

    {result, cursor_after}
  end

  def list_recipes(cursor_after, query \\ nil) do
    # return the next 50 posts
    query =
      case query do
        nil ->
          from recipe in Recipe, where: not is_nil(recipe.image_url)

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

    results = Repo.preload(entries, [:user])

    result =
      Enum.map(results, fn rec ->
        translate_recipe_if_needed(rec)
      end)

    {result, cursor_after}
  end

  def list_user_recipes(user_id) do
    query = from recipe in Recipe, where: recipe.user_id == ^user_id
    results = Repo.all(query)
    results = Repo.preload(results, [:recipe_ingredients, :user])

    result =
      Enum.map(results, fn rec ->
        translate_recipe_if_needed(rec)
      end)

    result
  end

  alias Mehungry.Food.Category

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs \\ %{}) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def create_ingredient(attrs) do
    Ingredient.changeset(%Ingredient{}, attrs)
    |> Repo.insert()
  end

  def delete_ingredient(%Ingredient{} = ingredient) do
    Repo.delete(ingredient)
  end

  def ingredient_display_names(ingredient_ids, language_name)
      when is_list(ingredient_ids) and language_name not in [nil, "en", "En"] do
    from(t in IngredientTranslation,
      where: t.language_name == ^language_name and t.ingredient_id in ^ingredient_ids,
      select: {t.ingredient_id, t.name}
    )
    |> Repo.all()
    |> Map.new()
  end

  def ingredient_display_names(_ingredient_ids, _language), do: %{}

  def count_untranslated_ingredients(language_name) do
    translated_ids =
      from t in IngredientTranslation,
        where: t.language_name == ^language_name,
        select: t.ingredient_id

    Repo.aggregate(
      from(i in Ingredient, where: i.id not in subquery(translated_ids)),
      :count
    )
  end

  def ingredient_translation_stats do
    total = Repo.aggregate(Ingredient, :count)

    languages =
      Mehungry.Languages.list_languages()
      |> Enum.map(fn lang ->
        translated =
          Repo.aggregate(
            from(t in IngredientTranslation, where: t.language_name == ^lang.name),
            :count
          )

        %{language: lang.name, translated: translated, total: total}
      end)

    %{total: total, languages: languages}
  end

  def find_ingredient_translation(language_name, ingredient_id) do
    query =
      from in_tr in "ingredient_translations",
        where: ^language_name == in_tr.language_name and ^ingredient_id == in_tr.ingredient_id,
        select: in_tr.name

    Repo.all(query)
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

  defp get_ingredient_by_translation_name(name) do
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
    translation = find_ingredient_translation(lang_id, ingredient_id)

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

        Cachex.put(:recipes_cache, {__MODULE__, recipe.id}, recipe)

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

      interactions =
        nutrients
        |> Enum.reduce(%{}, fn {name, data}, acc ->
          amount = Map.get(data, :amount) || 0.0
          canonical = NutrientMerger.normalize_nutrient_name(name)
          Map.update(acc, canonical, amount, &(&1 + amount))
        end)
        |> NutrientInteractions.interactions_for_nutrient_map()
        |> Enum.map(&NutrientMerger.to_string_keys/1)

      duration =
        (System.monotonic_time() - start)
        |> System.convert_time_unit(:native, :millisecond)

      Logger.warning("nutrition calculation: #{duration}ms for recipe")

      changeset
      |> Ecto.Changeset.put_change(:nutrients, nutrients)
      |> Ecto.Changeset.put_change(:primary_nutrients_size, primary_size)
      |> Ecto.Changeset.put_change(:ingredient_interactions, interactions)
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
        %{
          recipe_id: recipe.id
        }
        |> Mehungry.RecipePutNutrientsWorker.new()
        |> Oban.insert()

        result

      _ ->
        result
    end
  end

  def count_recipes do
    Repo.aggregate(Recipe, :count)
  end

  def list_recipe_ids do
    Repo.all(from r in Recipe, select: r.id)
  end

  def enqueue_nutrient_recalculation_for_all do
    ids = list_recipe_ids()

    Enum.each(ids, fn id ->
      %{recipe_id: id}
      |> Mehungry.RecipePutNutrientsWorker.new()
      |> Oban.insert()
    end)

    length(ids)
  end

  def list_nutrients() do
    Repo.all(Mehungry.Food.Nutrient)
  end

  def list_key_nutrients() do
    import Ecto.Query
    Repo.all(from n in Mehungry.Food.Nutrient, order_by: [asc: n.rank], limit: 30)
  end

  def list_ingredients() do
    Repo.all(Ingredient)
    |> Repo.preload([:measurement_unit, :category])
  end

  def search_measurement_unit(term) do
    query =
      from mu in MeasurementUnit,
        where: ilike(mu.name, ^term)

    Repo.all(query)
  end

  def search_category(term) do
    term = "%" <> term <> "%"

    query =
      from mu in Category,
        where: ilike(mu.name, ^term)

    Repo.all(query)
  end

  def search_measurement_unit(search_term, language_str) do
    search_term = search_term <> "%"
    language = Repo.get_by(Language, name: language_str)

    Logger.info(
      "Searching for measurement unit with name: " <>
        search_term <>
        ", in: " <> language_str <> ", Identified as: #{inspect(language)}"
    )

    if is_nil(language) do
      query =
        from mu in MeasurementUnit,
          where: ilike(mu.name, ^search_term)

      Repo.all(query)
    else
      query =
        from mu_trans in MeasurementUnitTranslation,
          where: mu_trans.language_name == ^language.name

      query_search =
        from transl in query,
          where: ilike(transl.name, ^search_term)

      query_aggrigate =
        from tra in query_search,
          join: ing in MeasurementUnit,
          on: true,
          where: ing.id == tra.id,
          join: cat in Category,
          on: true,
          select: %MeasurementUnit{name: tra.name, id: ing.id}

      result = Repo.all(query_aggrigate)
      Logger.info("Search: " <> search_term <> " resulted: " <> inspect(result))
      result
    end
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

    {query, list_recipes(query)}
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

    {query, list_recipes(query)}
  end

  def search_recipe("") do
    query = from(r in Recipe)
    {query, list_recipes(query)}
  end

  def search_recipe(query_string) do
    query = Mehungry.Search.RecipeSearch.run(Recipe, query_string)
    {query, list_recipes(query)}
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
        category = get_category_by_name(x)

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

  def get_interactions_for_ingredients(ingredient_ids) do
    Mehungry.Food.NutrientInteractions.interactions_for_ingredients(ingredient_ids)
  end

  def get_interactions_for_recipe(recipe) do
    stored = Map.get(recipe, :ingredient_interactions, [])

    if is_list(stored) and stored != [] do
      Enum.map(stored, &atomize_interaction/1)
    else
      nutrients = recipe.nutrients || %{}

      if map_size(nutrients) == 0 do
        []
      else
        nutrient_map =
          Enum.reduce(nutrients, %{}, fn {name, data}, acc ->
            amount = Map.get(data, "amount") || Map.get(data, :amount) || 0.0
            canonical = NutrientMerger.normalize_nutrient_name(name)
            Map.update(acc, canonical, amount, &(&1 + amount))
          end)

        NutrientInteractions.interactions_for_nutrient_map(nutrient_map)
      end
    end
  end

  def enqueue_interaction_recalculation_for_all do
    enqueue_nutrient_recalculation_for_all()
  end

  defp atomize_interaction(i) do
    %{
      id: Map.get(i, "id", "") |> safe_to_atom(),
      type: Map.get(i, "type", "") |> safe_to_atom(),
      badge: Map.get(i, "badge", "tip") |> safe_to_atom(),
      label: Map.get(i, "label", ""),
      detail: Map.get(i, "detail", ""),
      source: Map.get(i, "source", ""),
      nutrient_a: Map.get(i, "nutrient_a"),
      nutrient_b: Map.get(i, "nutrient_b")
    }
  end

  defp safe_to_atom(str) when is_binary(str), do: String.to_existing_atom(str)
  defp safe_to_atom(atom) when is_atom(atom), do: atom
end
