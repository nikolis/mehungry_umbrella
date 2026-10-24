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
    CompoundTranslation,
    Ingredient,
    IngredientPortion,
    IngredientPortionTranslation,
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
        # Overlay any per-ingredient portion-description translations (written
        # under the ISO code by the hub) onto the carried English descriptions.
        codes = Locale.siblings(language_name)
        portion_ids = collect_ids(translated, & &1.ingredient_portion_id)
        portion_descrs = portion_desc_map(portion_ids, codes)

        translated =
          Enum.map(translated, fn %RecipeIngredient{} = ri ->
            %RecipeIngredient{ri | ingredient_portion: overlay_portion(ri.ingredient_portion, portion_descrs)}
          end)

        %Recipe{recipe | recipe_ingredients: translated}
    end
  end

  @doc """
  Overlays locale translations onto a recipe's **already-preloaded**
  `recipe_ingredients` — the ingredient name, its category name, and the
  measurement-unit name — leaving every other field (crucially the
  `RecipeIngredient` id and FKs) intact.

  Unlike `translate_ingredients_to/2` (inner-join based, used by the list
  surfaces), this **never drops an ingredient**: any ingredient/category/unit
  without a translation row for the locale keeps its stored English name. A
  locale maps to several `language_name` codes (ISO `el` + legacy `Gr`); both are
  matched and the canonical code wins. No-op for the source locale (`en`), a
  `nil` locale, or when `recipe_ingredients` isn't loaded.
  """
  def localize_recipe_ingredients(%Recipe{} = recipe, locale) do
    cond do
      locale in [nil, Locale.source()] -> recipe
      not is_list(recipe.recipe_ingredients) -> recipe
      true -> do_localize_recipe_ingredients(recipe, locale)
    end
  end

  defp do_localize_recipe_ingredients(recipe, locale) do
    codes = Locale.data_codes(locale)
    ris = recipe.recipe_ingredients

    ingredient_ids = collect_ids(ris, & &1.ingredient_id)
    unit_ids = collect_ids(ris, & &1.measurement_unit_id)
    category_ids = collect_ids(ris, fn ri -> ri.ingredient && ri.ingredient.category_id end)
    portion_ids = collect_ids(ris, & &1.ingredient_portion_id)

    ing_names = name_map(IngredientTranslation, :ingredient_id, ingredient_ids, codes)
    unit_names = name_map(MeasurementUnitTranslation, :measurement_unit_id, unit_ids, codes)
    cat_names = name_map(CategoryTranslation, :category_id, category_ids, codes)
    portion_descrs = portion_desc_map(portion_ids, codes)

    translated =
      Enum.map(ris, &overlay_recipe_ingredient(&1, ing_names, unit_names, cat_names, portion_descrs))

    %Recipe{recipe | recipe_ingredients: translated}
  end

  defp collect_ids(ris, fun) do
    ris |> Enum.map(fun) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  # Build `%{id => translated_name}` for the rows whose `language_name` is one of
  # `codes`, preferring the earliest (canonical) code when a row exists in more
  # than one.
  defp name_map(_schema, _key, [], _codes), do: %{}

  defp name_map(schema, key, ids, codes) do
    rank = codes |> Enum.with_index() |> Map.new()

    from(t in schema,
      where: field(t, ^key) in ^ids and t.language_name in ^codes,
      select: {field(t, ^key), t.language_name, t.name}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {id, lang, name}, acc ->
      r = Map.get(rank, lang, length(codes))

      case Map.get(acc, id) do
        {best, _} when best <= r -> acc
        _ -> Map.put(acc, id, {r, name})
      end
    end)
    |> Map.new(fn {id, {_r, name}} -> {id, name} end)
  end

  defp overlay_recipe_ingredient(%RecipeIngredient{} = ri, ing_names, unit_names, cat_names, portion_descrs) do
    %RecipeIngredient{
      ri
      | ingredient: overlay_ingredient(ri.ingredient, ing_names, cat_names),
        measurement_unit: overlay_unit(ri.measurement_unit, unit_names),
        ingredient_portion: overlay_portion(ri.ingredient_portion, portion_descrs)
    }
  end

  # Only a unit-less portion carries a translatable free-text description; leave
  # unit-bearing portions (and non-structs) untouched.
  defp overlay_portion(%IngredientPortion{measurement_unit_id: nil, id: id} = portion, portion_descrs) do
    case Map.get(portion_descrs, id) do
      nil -> portion
      desc -> %IngredientPortion{portion | description: desc}
    end
  end

  defp overlay_portion(other, _portion_descrs), do: other

  defp overlay_ingredient(%Ingredient{} = ing, ing_names, cat_names) do
    %Ingredient{
      ing
      | name: Map.get(ing_names, ing.id, ing.name),
        category: overlay_category(ing.category, cat_names)
    }
  end

  defp overlay_ingredient(other, _ing_names, _cat_names), do: other

  defp overlay_category(%Category{} = cat, cat_names) do
    %Category{cat | name: Map.get(cat_names, cat.id, cat.name)}
  end

  defp overlay_category(other, _cat_names), do: other

  defp overlay_unit(%MeasurementUnit{} = mu, unit_names) do
    %MeasurementUnit{mu | name: Map.get(unit_names, mu.id, mu.name)}
  end

  defp overlay_unit(other, _unit_names), do: other

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

  @doc """
  Like `ingredient_display_names/2` but keyed on the ingredient's base `name`
  instead of its id — for surfaces that only carry names (e.g. a published plan's
  grocery list). Returns `%{base_name => translated_name}` for the given
  `language_name`; empty for English (base names are already English).
  """
  def ingredient_display_names_by_name(names, language_name)
      when is_list(names) and names != [] and language_name not in [nil, "en", "En"] do
    from(t in IngredientTranslation,
      join: i in assoc(t, :ingredient),
      where: t.language_name == ^language_name and i.name in ^names,
      select: {i.name, t.name}
    )
    |> Repo.all()
    |> Map.new()
  end

  def ingredient_display_names_by_name(_names, _language), do: %{}

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

  @doc """
  `%{measurement_unit_id => translated_name}` for the given unit ids and
  `locale`. Locale-aware sibling of `get_unit_translations_map/2`: matches every
  `language_name` the locale maps to (ISO `el` + legacy `Gr`) via
  `Locale.data_codes/1`, the canonical code winning. Returns `%{}` for the source
  locale so callers no-op cleanly.
  """
  def unit_display_names(unit_ids, locale)
      when is_list(unit_ids) and unit_ids != [] and locale not in [nil, "en", "En"] do
    name_map(MeasurementUnitTranslation, :measurement_unit_id, unit_ids, Locale.data_codes(locale))
  end

  def unit_display_names(_unit_ids, _locale), do: %{}

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

  @doc """
  `%{ingredient_portion_id => translated_description}` for the given portion ids
  and `locale`. Portion translations live in `ingredient_portion_translations`
  and are keyed by ISO or legacy code (`Locale.data_codes/1`); the canonical code
  wins. Returns `%{}` for the source locale so callers no-op cleanly.
  """
  def portion_display_names(portion_ids, locale)
      when is_list(portion_ids) and portion_ids != [] and locale not in [nil, "en", "En"] do
    portion_desc_map(portion_ids, Locale.data_codes(locale))
  end

  def portion_display_names(_portion_ids, _locale), do: %{}

  @doc """
  List `%{portion: %IngredientPortion{}, translation: %IngredientPortionTranslation{} | nil}`
  pairs for an ingredient's **unit-less, meaningful** portions (the only ones the
  translation hub translates — unit-bearing portions get their label from the
  measurement-unit translation). Drives the hub's per-ingredient portion editor.
  """
  def list_portion_translation_pairs(ingredient_id, locale) do
    codes = Locale.data_codes(locale)

    portions =
      from(p in IngredientPortion,
        where: p.ingredient_id == ^ingredient_id and is_nil(p.measurement_unit_id),
        order_by: [asc: p.id]
      )
      |> Repo.all()
      |> Enum.filter(&IngredientPortion.meaningful_label?(&1.description))

    tmap = portion_translation_rows(Enum.map(portions, & &1.id), codes)

    Enum.map(portions, fn p -> %{portion: p, translation: Map.get(tmap, p.id)} end)
  end

  @doc """
  Ingredient ids that have at least one unit-less free-text portion still lacking
  a translation for `locale`. Powers the hub's "AI-translate missing portions"
  bulk action, which targets otherwise-translated ingredients whose portions were
  never translated. `:limit` bounds the result.
  """
  def ingredient_ids_with_untranslated_portions(locale, opts \\ []) do
    query = untranslated_portion_ingredient_ids_query(Locale.data_codes(locale))

    query =
      case Keyword.get(opts, :limit) do
        nil -> query
        limit -> limit(query, ^limit)
      end

    Repo.all(query)
  end

  @doc "Count of ingredients matching `ingredient_ids_with_untranslated_portions/1`."
  def count_ingredients_with_untranslated_portions(locale) do
    sub = untranslated_portion_ingredient_ids_query(Locale.data_codes(locale))
    Repo.one(from(s in subquery(sub), select: count()))
  end

  defp untranslated_portion_ingredient_ids_query(codes) do
    translated =
      from(t in IngredientPortionTranslation,
        where: t.language_name in ^codes,
        select: t.ingredient_portion_id
      )

    from(p in IngredientPortion,
      where:
        not is_nil(p.ingredient_id) and is_nil(p.measurement_unit_id) and
          not is_nil(p.description) and p.description != "" and
          p.id not in subquery(translated),
      distinct: true,
      select: p.ingredient_id
    )
  end

  @doc """
  Upsert the translation of a portion's free-text description for `(portion_id,
  locale)`. Writes under the locale's canonical ISO code and stamps verification
  on `"verified"`. Used by the hub's manual save and the bulk AI worker.
  """
  def upsert_portion_translation(portion_id, locale, description, opts \\ []) do
    status = Keyword.get(opts, :status, "verified")
    write_code = Locale.write_code(locale)
    Mehungry.Languages.ensure_language(write_code)

    attrs =
      %{
        ingredient_portion_id: portion_id,
        language_name: write_code,
        description: description,
        status: status
      }
      |> stamp_portion_verification(status, opts)

    struct =
      Repo.get_by(IngredientPortionTranslation,
        ingredient_portion_id: portion_id,
        language_name: write_code
      ) || %IngredientPortionTranslation{ingredient_portion_id: portion_id}

    struct
    |> IngredientPortionTranslation.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp stamp_portion_verification(attrs, "verified", opts) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs
    |> Map.put(:verified_at, now)
    |> Map.put(:verified_by_id, Keyword.get(opts, :verified_by_id))
  end

  defp stamp_portion_verification(attrs, _status, _opts), do: attrs

  # `%{portion_id => translated_description}`, preferring the earliest (canonical)
  # code when a portion has rows under more than one of `codes`.
  defp portion_desc_map([], _codes), do: %{}

  defp portion_desc_map(portion_ids, codes) do
    rank = codes |> Enum.with_index() |> Map.new()

    from(t in IngredientPortionTranslation,
      where: t.ingredient_portion_id in ^portion_ids and t.language_name in ^codes,
      select: {t.ingredient_portion_id, t.language_name, t.description}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {id, lang, desc}, acc ->
      r = Map.get(rank, lang, length(codes))

      case Map.get(acc, id) do
        {best, _} when best <= r -> acc
        _ -> Map.put(acc, id, {r, desc})
      end
    end)
    |> Map.new(fn {id, {_r, desc}} -> {id, desc} end)
  end

  # Like `portion_desc_map/2` but returns the full preferred translation row per
  # portion (so the hub editor can show status), not just the description string.
  defp portion_translation_rows([], _codes), do: %{}

  defp portion_translation_rows(portion_ids, codes) do
    rank = codes |> Enum.with_index() |> Map.new()

    from(t in IngredientPortionTranslation,
      where: t.ingredient_portion_id in ^portion_ids and t.language_name in ^codes
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn t, acc ->
      r = Map.get(rank, t.language_name, length(codes))

      case Map.get(acc, t.ingredient_portion_id) do
        {best, _} when best <= r -> acc
        _ -> Map.put(acc, t.ingredient_portion_id, {r, t})
      end
    end)
    |> Map.new(fn {id, {_r, t}} -> {id, t} end)
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

  @doc """
  `%{compound_id => translated_name}` for the given compound ids and `locale`.

  Compound translations live in `compound_translations` (curated/AI-drafted at
  `/professional/translations`). Rows may be keyed by the ISO code or a legacy
  alias (`Locale.data_codes/1`); the ISO row wins when both exist. Returns `%{}`
  for the source locale so callers no-op cleanly.
  """
  def compound_display_names(compound_ids, locale)
      when is_list(compound_ids) and locale not in [nil, "en", "En"] do
    codes = Locale.data_codes(locale)
    iso = Locale.write_code(locale)

    from(t in CompoundTranslation,
      where: t.language_name in ^codes and t.compound_id in ^compound_ids,
      select: {t.compound_id, t.language_name, t.name}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {cid, lang, name}, acc ->
      cond do
        not Map.has_key?(acc, cid) -> Map.put(acc, cid, {lang, name})
        # ISO row overrides a previously-seen legacy row.
        lang == iso -> Map.put(acc, cid, {lang, name})
        true -> acc
      end
    end)
    |> Map.new(fn {cid, {_lang, name}} -> {cid, name} end)
  end

  def compound_display_names(_compound_ids, _locale), do: %{}
end
