defmodule Mehungry.Food.Localization do
  @moduledoc """
  Recipe, ingredient, category, and measurement-unit translations:
  bulk localization of recipe lists, per-recipe translation application,
  translation upserts, and translation coverage stats.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo

  alias Mehungry.Food.{
    Category,
    CategoryTranslation,
    Ingredient,
    IngredientPortion,
    IngredientTranslation,
    MeasurementUnit,
    MeasurementUnitTranslation,
    Recipe,
    RecipeIngredient
  }

  alias Mehungry.AI.Bot.RecipeTranslation
  alias Mehungry.Languages.{Language, Locale}

  def apply_recipe_translation(recipe, nil), do: recipe
  def apply_recipe_translation(recipe, %RecipeTranslation{title: nil}), do: recipe

  def apply_recipe_translation(recipe, %RecipeTranslation{} = translation) do
    %{
      recipe
      | title: translation.title || recipe.title,
        description: translation.description || recipe.description,
        steps: apply_step_translations(recipe.steps, translation.steps)
    }
  end

  # Overlays translated step descriptions onto the recipe's embedded `Step`s,
  # matched by `index` (the translator stores `[%{"index" => i, "description" =>
  # d}]`). A step with no/blank translation keeps its base text; step titles are
  # not translated. Handles both string- and atom-keyed maps.
  defp apply_step_translations(steps, translated) when translated in [nil, []], do: steps

  defp apply_step_translations(steps, translated) do
    by_index =
      Enum.reduce(translated, %{}, fn s, acc ->
        idx = Map.get(s, "index", Map.get(s, :index))
        desc = Map.get(s, "description", Map.get(s, :description))

        if is_nil(idx) or desc in [nil, ""], do: acc, else: Map.put(acc, idx, desc)
      end)

    Enum.map(steps, fn step ->
      case Map.get(by_index, step.index) do
        nil -> step
        desc -> %{step | description: desc}
      end
    end)
  end

  # Bulk-apply user-language translations to a list of recipes, sorting translated ones first.
  def localize_recipes(recipes, nil), do: Enum.map(recipes, &translate_recipe_if_needed/1)

  def localize_recipes(recipes, language_name) do
    recipe_ids = Enum.map(recipes, & &1.id)
    translations = load_recipe_translations_map(recipe_ids, language_name)
    ing_lang = ingredient_language_for(language_name)

    recipes
    |> Enum.sort_by(fn rec -> if Map.has_key?(translations, rec.id), do: 0, else: 1 end)
    |> Enum.map(fn rec ->
      translation = Map.get(translations, rec.id)

      if translation && ing_lang do
        rec
        |> apply_recipe_translation(translation)
        |> translate_ingredients_to(ing_lang)
      else
        rec
        |> apply_recipe_translation(translation)
        |> translate_recipe_if_needed()
      end
    end)
  end

  def load_recipe_translations_map([], _language_name), do: %{}

  def load_recipe_translations_map(recipe_ids, language_name) do
    # A locale maps to several `language_name` codes (canonical ISO + legacy
    # alias, e.g. "el" + "Gr"); match all of them and prefer the canonical row
    # when a recipe carries both.
    codes = Locale.data_codes(language_name)
    rank = codes |> Enum.with_index() |> Map.new()

    from(rt in RecipeTranslation,
      where: rt.recipe_id in ^recipe_ids and rt.language_name in ^codes
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn rt, acc ->
      r = Map.get(rank, rt.language_name, length(codes))

      case Map.get(acc, rt.recipe_id) do
        {best, _} when best <= r -> acc
        _ -> Map.put(acc, rt.recipe_id, {r, rt})
      end
    end)
    |> Map.new(fn {id, {_r, rt}} -> {id, rt} end)
  end

  def translate_recipe_if_needed(recipe) do
    language =
      from(lan in Language,
        where: lan.name == ^recipe.language_name
      )
      |> Repo.one()

    case language do
      %{name: "Gr"} ->
        translate_ingredients_to(recipe, "Gr")

      _ ->
        recipe
        |> Repo.preload([
          :user,
          {:recipe_ingredients,
           [
             {:measurement_unit, :translation},
             :ingredient_portion,
             {:ingredient, :category}
           ]}
        ])
    end
  end

  @doc """
  Maps user language preference codes to the ingredient translation language
  codes. Ingredient/category/unit translations use the legacy "Gr"/"En"
  naming scheme.
  """
  def ingredient_language_for("el"), do: "Gr"
  def ingredient_language_for(_), do: nil

  def translate_ingredients_to(%Recipe{} = recipe, language_name) do
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
        where: cat_trans.category_id == cat.id and ^language_name == cat_trans.language_name,
        # LEFT joins so description-only rows (no measurement unit) survive; the
        # portion is carried so RecipeIngredient.unit_label/1 can fall back to
        # its free-text description at render time.
        left_join: mu in MeasurementUnit,
        on: mu.id == rec_ing.measurement_unit_id,
        left_join: mu_trans in MeasurementUnitTranslation,
        on: mu_trans.measurement_unit_id == mu.id and ^language_name == mu_trans.language_name,
        left_join: portion in IngredientPortion,
        on: portion.id == rec_ing.ingredient_portion_id,
        select: %RecipeIngredient{
          quantity: rec_ing.quantity,
          ingredient_allias: rec_ing.ingredient_allias,
          measurement_unit_id: rec_ing.measurement_unit_id,
          ingredient_portion_id: rec_ing.ingredient_portion_id,
          measurement_unit: %MeasurementUnit{id: mu.id, name: mu_trans.name},
          ingredient_portion: %IngredientPortion{id: portion.id, description: portion.description},
          ingredient: %Ingredient{
            name: tra.name,
            id: ingredient.id,
            measurement_unit: %MeasurementUnit{id: mu.id, name: mu_trans.name},
            category: %Category{id: cat.id, name: cat_trans.name}
          }
        }

    case Repo.all(query) do
      [] ->
        Repo.preload(recipe, [
          {:recipe_ingredients,
           [:measurement_unit, :ingredient_portion, {:ingredient, :category}]}
        ])

      translated ->
        %Recipe{recipe | recipe_ingredients: translated}
    end
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

  def get_unit_translations_map(unit_ids, language_name)
      when language_name not in [nil, "en", "En"] do
    from(t in MeasurementUnitTranslation,
      where: t.language_name == ^language_name and t.measurement_unit_id in ^unit_ids,
      select: {t.measurement_unit_id, t.name}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_unit_translations_map(_unit_ids, _language), do: %{}

  def upsert_ingredient_translation(ingredient_id, language_name, name) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert(
      %IngredientTranslation{
        ingredient_id: ingredient_id,
        language_name: language_name,
        name: name,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: {:replace, [:name, :updated_at]},
      conflict_target: [:ingredient_id, :language_name]
    )
  end

  def upsert_measurement_unit_translation(unit_id, language_name, name) do
    case Repo.get_by(MeasurementUnitTranslation,
           measurement_unit_id: unit_id,
           language_name: language_name
         ) do
      nil ->
        %MeasurementUnitTranslation{measurement_unit_id: unit_id}
        |> MeasurementUnitTranslation.changeset(%{language_name: language_name, name: name})
        |> Repo.insert()

      existing ->
        existing
        |> MeasurementUnitTranslation.changeset(%{name: name})
        |> Repo.update()
    end
  end

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
end
