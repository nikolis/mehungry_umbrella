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
    IngredientPortion
  }

  alias Mehungry.Languages.Language

  def create_ingredient_portion(attrs) do
    %IngredientPortion{}
    |> IngredientPortion.changeset(attrs)
    |> Repo.insert()
  end

  def create_ingredient_nutrient(attrs) do
    %IngredientNutrient{}
    |> IngredientNutrient.changeset(attrs)
    |> Repo.insert()
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

  #  def annotate_recipe(%User{id: user_id}, recipe_id, attrs) do
  #    %Annotation{recipe_id: recipe_id, user_id: user_id}
  #    |> Annotation.changeset(attrs)
  #    |> Repo.insert()
  #  end

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

  def get_measurement_unit!(id) do
    Repo.get(MeasurementUnit, id)
  end

  def get_measurement_unit_by_name(name) do
    from(mu in MeasurementUnit,
      where: mu.name == ^name or mu.alternate_name == ^name
    )
    |> Repo.all()
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

    Repo.delete(recipe)
  end

  def get_recipe!(id) do
    result =
      Repo.get(Recipe, id)
      |> Repo.preload([[recipe_ingredients: [:measurement_unit, :ingredient]], :user])

    if is_nil(result) do
      result
    else
      translate_recipe_if_needed(result)
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

  def list_recipes(cursor_after) do
    query = from recipe in Recipe, where: not is_nil(recipe.image_url)
    # return the next 50 posts

    %{entries: entries, metadata: metadata} =
      Repo.paginate(
        query,
        after: cursor_after,
        cursor_fields: [{:inserted_at, :asc}, {:id, :asc}],
        limit: 10
      )

    # assign the `after` cursor to a variable
    cursor_after = metadata.after

    results = Repo.preload(entries, [:recipe_ingredients, :user])

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

  def recipes_with_average_ratings(%{
        age_group_filter: age_group_filter
      }) do
    Recipe.Query.with_average_ratings()
    |> Recipe.Query.join_users()
    |> Recipe.Query.join_demographics()
    |> Recipe.Query.filter_by_age_group(age_group_filter)
    |> Repo.all()
  end

  def recipes_with_zero_ratings do
    Recipe.Query.with_zero_ratings()
    |> Repo.all()
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

  def get_ingredient_details!(id) do
    Repo.get!(Ingredient, id)
    |> Repo.preload(
      ingredient_portions: [:measurement_unit],
      ingredient_nutrients: [nutrient: [:measurement_unit]]
    )
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

  def update_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    recipe
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  def create_post_from_recipe(%Recipe{} = recipe) do
    post_params = %{
      md_media_url: recipe.image_url,
      description: recipe.description,
      reference_id: recipe.id,
      title: recipe.title,
      type_: "RECIPE",
      user_id: recipe.user_id,
      recipe_id: recipe.id
    }

    Mehungry.Posts.create_post(post_params)
  end

  def create_recipe(attrs \\ %{}) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  def list_ingredients() do
    Repo.all(Ingredient)
    |> Repo.preload([:measurement_unit, :category])
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
          where: mu_trans.language_name == ^language.id

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

  def search_recipe(query_string) do
    query = Mehungry.Search.RecipeSearch.run(Recipe, query_string)
    list_recipes(query)
  end

  def search_ingredient(search_term, language_name) do
    search_term = search_term <> "%"

    Logger.info(
      "Searching for ingredient with name: " <>
        search_term <>
        ", in: " <> language_name
    )

    if is_nil(language_name) do
      query =
        from ingredient in Ingredient,
          where: ilike(ingredient.name, ^search_term)

      Repo.all(query)
      |> Repo.preload([:category, :measurement_unit])
    else
      if is_nil(language_name) do
        Logger.info("Language not fount" <> language_name)
        []
      else
        Logger.info("Language no doupt" <> language_name)

        query =
          from ingr_trans in IngredientTranslation,
            where: ingr_trans.language_name == ^language_name

        query_search =
          from transl in query,
            where: ilike(transl.name, ^search_term)

        query_aggrigate =
          from tra in query_search,
            inner_join: ing in Ingredient,
            on: ing.id == tra.ingredient_id,
            inner_join: cat in Category,
            on: true,
            where: cat.id == ing.category_id,
            inner_join: cat_trans in CategoryTranslation,
            on: true,
            where: cat_trans.category_id == cat.id and cat_trans.language_name == ^language_name,
            inner_join: mu in MeasurementUnit,
            on: true,
            where: mu.id == ing.measurement_unit_id,
            inner_join: mu_trans in MeasurementUnitTranslation,
            on: true,
            where:
              mu_trans.measurement_unit_id == mu.id and mu_trans.language_name == ^language_name,
            distinct: true,
            select: %Ingredient{
              name: tra.name,
              id: ing.id,
              category: %Category{id: cat.id, name: cat_trans.name},
              measurement_unit: %MeasurementUnit{id: mu.id, name: mu_trans.name}
            }

        result = Repo.all(query_aggrigate)
        Logger.info("Search: " <> search_term <> " resulted: " <> inspect(result))
        result
      end
    end
  end

  def list_recipes_with_user_rating(user) do
    Recipe.Query.with_user_ratings(user)
    |> Repo.all()
  end
end
