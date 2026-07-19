defmodule Mehungry.Food do
  @moduledoc """
  Facade for the Food context.

  The implementation is split by concern into sub-modules; every public
  function remains callable through this module so existing call sites keep
  working. New code may call the sub-modules directly:

    * `Mehungry.Food.Recipes` — recipe CRUD, listings, counts, cache
    * `Mehungry.Food.Ingredients` — ingredient CRUD, lookups, pagination
    * `Mehungry.Food.IngredientQueries` — ingredient/recipe/hashtag search
    * `Mehungry.Food.Nutrients` — nutrient records and interactions
    * `Mehungry.Food.Measurements` — measurement units and portions
    * `Mehungry.Food.Categories` — categories and food restriction types
    * `Mehungry.Food.Localization` — recipe/ingredient/unit translations
    * `Mehungry.Food.Engagement` — likes, comments, annotations
  """

  alias Mehungry.Food.{
    Categories,
    Engagement,
    IngredientQueries,
    Ingredients,
    Localization,
    Measurements,
    Nutrients,
    Recipes
  }

  # ── Recipes ────────────────────────────────────────────────────────────

  defdelegate get_recipe_no_caching!(id), to: Recipes
  defdelegate get_recipe!(id), to: Recipes
  defdelegate get_recipe!(id, language_name), to: Recipes
  defdelegate delete_recipe(id), to: Recipes
  defdelegate change_recipe(recipe, attrs \\ %{}), to: Recipes
  defdelegate change_step(step, attrs \\ %{}), to: Recipes
  defdelegate create_recipe(attrs \\ %{}), to: Recipes
  defdelegate update_recipe(recipe_origin, attrs \\ %{}), to: Recipes
  defdelegate create_post_from_recipe(recipe), to: Recipes
  defdelegate put_nutrient_info(changeset, attrs), to: Recipes
  defdelegate recipe_counts_by_user_id(), to: Recipes
  defdelegate count_user_created_recipes(user_id), to: Recipes
  defdelegate count_recipes_created_by_user_ids(user_ids), to: Recipes
  defdelegate count_recipes(), to: Recipes
  defdelegate count_recipes_missing_embeddings(), to: Recipes
  defdelegate list_recipe_ids(), to: Recipes
  defdelegate list_recipes(query_or_cursor), to: Recipes
  defdelegate list_recipes(query_or_cursor, language_or_query), to: Recipes
  defdelegate list_recipes(cursor_after, query, language_name), to: Recipes
  defdelegate list_user_recipes(user_id), to: Recipes
  defdelegate list_user_recipes_for_selection(user_id), to: Recipes

  # ── Ingredients ────────────────────────────────────────────────────────

  defdelegate create_ingredient_portion(attrs), to: Ingredients
  defdelegate broadcast_ingredient_work_item(file_url), to: Ingredients
  defdelegate create_ingredient_nutrient(attrs), to: Ingredients
  defdelegate get_ingredient_by_name(name), to: Ingredients
  defdelegate create_ingredient(attrs), to: Ingredients
  defdelegate delete_ingredient(ingredient), to: Ingredients
  defdelegate delete_ingredients_without_nutrients(), to: Ingredients
  defdelegate change_ingredient(ingredient, attrs \\ %{}), to: Ingredients
  defdelegate update_ingredient(ingredient, attrs \\ %{}), to: Ingredients
  defdelegate get_ingredient_by_slug(slug), to: Ingredients
  defdelegate get_ingredient_by_translation_name(name), to: Ingredients
  defdelegate get_ingredient_details!(id), to: Ingredients
  defdelegate get_ingredient_with_category!(id), to: Ingredients
  defdelegate get_ingredient!(id), to: Ingredients
  defdelegate get_ingredient(id), to: Ingredients
  defdelegate find_ri_allias(rec_in, lang_id), to: Ingredients
  defdelegate list_ingredients(), to: Ingredients
  defdelegate list_ingredients_paginated(), to: Ingredients
  defdelegate list_ingredients_paginated(query_or_cursor), to: Ingredients
  defdelegate list_ingredients_paginated(cursor_after, query), to: Ingredients
  defdelegate list_ingredients_paginated_translated(language_name, cursor_after \\ nil),
    to: Ingredients

  defdelegate list_recipe_ingredients(), to: Ingredients
  defdelegate change_recipe_ingredient(recipe_ingredient, attrs \\ %{}), to: Ingredients

  # ── Search / queries ───────────────────────────────────────────────────

  defdelegate search_hashtag(hashtag), to: IngredientQueries
  defdelegate search_hashtag1(hashtag), to: IngredientQueries
  defdelegate search_recipes_by_ingredient(ingredient_name), to: IngredientQueries
  defdelegate list_sample_recipes_for_ingredient(ingredient_id, limit \\ 4), to: IngredientQueries
  defdelegate search_recipe(query_string, language_name \\ nil), to: IngredientQueries
  defdelegate pagenate_query(query), to: IngredientQueries
  defdelegate get_second_layer_foods_ids(), to: IngredientQueries
  defdelegate maybe_filter_by_classes(query, classes), to: IngredientQueries
  defdelegate search_ingredient_search(search_term, classes \\ []), to: IngredientQueries
  defdelegate search_ingredient_alt_admin(search_term, classes \\ []), to: IngredientQueries
  defdelegate search_ingredient_alt(search_term, classes \\ []), to: IngredientQueries
  defdelegate search_ingredient_admin(search_term, classes \\ []), to: IngredientQueries

  defdelegate search_ingredient_admin_translated(search_term, language_name, classes \\ []),
    to: IngredientQueries

  defdelegate search_ingredient(search_term, classes \\ []), to: IngredientQueries
  defdelegate search_ingredient_query(search_term, classes \\ []), to: IngredientQueries
  defdelegate search_ingredient3(search_term), to: IngredientQueries
  defdelegate search_ingredient2(search_term), to: IngredientQueries

  # ── Nutrients ──────────────────────────────────────────────────────────

  defdelegate get_nutrient(id), to: Nutrients
  defdelegate get_nutrient(name, measurement_unit_id), to: Nutrients
  defdelegate create_nutrient(attrs), to: Nutrients
  defdelegate list_nutrients(), to: Nutrients
  defdelegate list_key_nutrients(), to: Nutrients
  defdelegate enqueue_nutrient_recalculation_for_all(), to: Nutrients
  defdelegate get_interactions_for_ingredients(ingredient_ids), to: Nutrients
  defdelegate get_interactions_for_recipe(recipe), to: Nutrients
  defdelegate enqueue_interaction_recalculation_for_all(), to: Nutrients

  # ── Measurements ───────────────────────────────────────────────────────

  defdelegate get_measurement_unit!(id), to: Measurements
  defdelegate get_measurement_unit_portions_for_ingredient(ingredient_id), to: Measurements
  defdelegate get_measurement_unit_portions_for_ingredients(ingredient_ids), to: Measurements
  defdelegate get_measurement_unit_by_name(name), to: Measurements
  defdelegate create_measurement_unit(attrs), to: Measurements
  defdelegate update_measurement_unit(measurement_unit, attrs \\ %{}), to: Measurements
  defdelegate delete_measurement_unit(measurement_unit), to: Measurements
  defdelegate change_measurement_unit(measurement_unit, attrs \\ %{}), to: Measurements
  defdelegate list_measurement_units(), to: Measurements
  defdelegate search_measurement_unit(term), to: Measurements
  defdelegate search_measurement_unit(search_term, language_str), to: Measurements

  # ── Categories ─────────────────────────────────────────────────────────

  defdelegate create_category(attrs), to: Categories
  defdelegate update_category(category, attrs \\ %{}), to: Categories
  defdelegate delete_category(category), to: Categories
  defdelegate get_category!(id), to: Categories
  defdelegate change_category(category, attrs \\ %{}), to: Categories
  defdelegate get_category_by_name(name), to: Categories
  defdelegate list_categories(), to: Categories
  defdelegate search_category(term), to: Categories
  defdelegate list_food_restriction_types(), to: Categories

  # ── Localization ───────────────────────────────────────────────────────

  defdelegate apply_recipe_translation(recipe, translation), to: Localization
  defdelegate localize_recipes(recipes, language_name), to: Localization
  defdelegate load_recipe_translations_map(recipe_ids, language_name), to: Localization
  defdelegate translate_recipe_if_needed(recipe), to: Localization
  defdelegate ingredient_display_names(ingredient_ids, language_name), to: Localization
  defdelegate get_unit_translations_map(unit_ids, language_name), to: Localization

  defdelegate upsert_ingredient_translation(ingredient_id, language_name, name),
    to: Localization

  defdelegate upsert_measurement_unit_translation(unit_id, language_name, name),
    to: Localization

  defdelegate count_untranslated_ingredients(language_name), to: Localization
  defdelegate ingredient_translation_stats(), to: Localization
  defdelegate find_ingredient_translation(language_name, ingredient_id), to: Localization

  # ── Engagement ─────────────────────────────────────────────────────────

  defdelegate get_user_likes(user_id), to: Engagement
  defdelegate like_recipe(user_id, recipe_id), to: Engagement
  defdelegate count_user_liked_recipes(user_id), to: Engagement
  defdelegate get_recipe_comments(recipe_id), to: Engagement
  defdelegate list_annotations(recipe), to: Engagement
end
