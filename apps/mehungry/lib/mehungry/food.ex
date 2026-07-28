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
    * `Mehungry.Food.Taxonomies` — hierarchical ingredient taxonomies
    * `Mehungry.Food.Enrichment` — scientific enrichment sidecar
    * `Mehungry.Food.IdentityResolution` — scientific identity resolution
    * `Mehungry.Food.Compounds` — bioactive compound knowledge (scientific facts)
    * `Mehungry.Food.CompoundMeasurements` — quantitative compound measurements (immutable)
    * `Mehungry.Food.EvidenceAggregation` — read-only summaries of compound measurements
    * `Mehungry.Food.Localization` — recipe/ingredient/unit translations
    * `Mehungry.Food.Engagement` — likes, comments, annotations
  """

  alias Mehungry.Food.{
    Categories,
    CompoundCandidates,
    Compounds,
    CompoundMeasurements,
    Engagement,
    Enrichment,
    EvidenceAggregation,
    IdentityResolution,
    IdentityResolutionRuns,
    IngredientQueries,
    Ingredients,
    Localization,
    Measurements,
    Nutrients,
    Recipes,
    Taxonomies,
    TaxonomyClassificationRuns
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
  defdelegate delete_branded_ingredients(), to: Ingredients
  defdelegate change_ingredient(ingredient, attrs \\ %{}), to: Ingredients
  defdelegate update_ingredient(ingredient, attrs \\ %{}), to: Ingredients
  defdelegate get_ingredient_by_slug(slug), to: Ingredients
  defdelegate enqueue_ingredient_backfill(), to: Ingredients
  defdelegate reconciliation_progress(), to: Ingredients
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
  defdelegate count_search_results(query), to: IngredientQueries
  defdelegate get_second_layer_foods_ids(), to: IngredientQueries
  defdelegate maybe_filter_by_classes(query, classes), to: IngredientQueries
  defdelegate maybe_filter_by_data_types(query, data_types), to: IngredientQueries
  defdelegate list_distinct_food_classes(), to: IngredientQueries
  defdelegate list_distinct_data_types(), to: IngredientQueries
  defdelegate search_ingredient_search(search_term, classes \\ []), to: IngredientQueries

  defdelegate search_ingredient_alt_admin(search_term, classes \\ [], data_types \\ []),
    to: IngredientQueries

  defdelegate search_ingredient_alt(search_term, classes \\ []), to: IngredientQueries

  defdelegate search_ingredient_admin(search_term, classes \\ [], data_types \\ []),
    to: IngredientQueries

  defdelegate search_ingredient_admin_translated(
                search_term,
                language_name,
                classes \\ [],
                data_types \\ []
              ),
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
  defdelegate create_measurement_unit(attrs, opts), to: Measurements
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

  # ── Taxonomies ─────────────────────────────────────────────────────────

  defdelegate create_taxonomy(attrs), to: Taxonomies
  defdelegate get_taxonomy!(id), to: Taxonomies
  defdelegate get_taxonomy_by_slug(slug), to: Taxonomies
  defdelegate list_taxonomies(), to: Taxonomies
  defdelegate create_node(attrs), to: Taxonomies
  defdelegate update_node(node, attrs), to: Taxonomies
  defdelegate delete_node(node), to: Taxonomies
  defdelegate get_node!(id), to: Taxonomies
  defdelegate get_node_by_slug(taxonomy_id, slug), to: Taxonomies
  defdelegate list_nodes(taxonomy_id), to: Taxonomies
  defdelegate list_leaf_nodes(taxonomy_id), to: Taxonomies
  defdelegate list_leaves_with_paths(taxonomy_id), to: Taxonomies
  defdelegate build_tree(taxonomy_id), to: Taxonomies
  defdelegate subtree_node_ids(node_id), to: Taxonomies
  defdelegate list_ingredients_under_node(node_id), to: Taxonomies
  defdelegate attach_ingredient(ingredient_id, node_id, attrs \\ %{}), to: Taxonomies
  defdelegate detach_ingredient(ingredient_id, node_id), to: Taxonomies
  defdelegate get_ingredient_node_id(taxonomy_id, ingredient_id), to: Taxonomies
  defdelegate set_ingredient_node(taxonomy_id, ingredient_id, node_id), to: Taxonomies
  defdelegate list_pending_review(taxonomy_id, opts \\ []), to: Taxonomies
  defdelegate review_mapping(id, action), to: Taxonomies
  defdelegate classification_progress(taxonomy_id), to: Taxonomies
  defdelegate enqueue_classification(taxonomy_id), to: Taxonomies

  defdelegate latest_classification_run(taxonomy_id),
    to: TaxonomyClassificationRuns,
    as: :latest_run

  # ── Enrichment (scientific sidecar) ────────────────────────────────────

  defdelegate create_enrichment_source(attrs), to: Enrichment
  defdelegate get_enrichment_source!(id), to: Enrichment
  defdelegate list_enrichment_sources(), to: Enrichment
  defdelegate upsert_enrichment_source(attrs), to: Enrichment
  defdelegate create_scientific_property(attrs), to: Enrichment
  defdelegate upsert_scientific_property(attrs), to: Enrichment
  defdelegate list_scientific_properties(ingredient_id), to: Enrichment
  defdelegate delete_scientific_property(property), to: Enrichment
  defdelegate create_classification(attrs), to: Enrichment
  defdelegate upsert_classification(attrs), to: Enrichment
  defdelegate list_classifications(ingredient_id), to: Enrichment
  defdelegate delete_classification(classification), to: Enrichment
  defdelegate create_health_attribute(attrs), to: Enrichment
  defdelegate upsert_health_attribute(attrs), to: Enrichment
  defdelegate list_health_attributes(ingredient_id), to: Enrichment
  defdelegate delete_health_attribute(attribute), to: Enrichment
  defdelegate list_enrichment(ingredient_id), to: Enrichment

  # ── Identity resolution (scientific identifiers) ───────────────────────

  defdelegate enqueue_resolution(), to: IdentityResolution
  defdelegate resolve_ingredient(ingredient), to: IdentityResolution
  defdelegate resolution_progress(), to: IdentityResolution
  defdelegate add_identity_candidate(attrs), to: IdentityResolution
  defdelegate get_identity!(id), to: IdentityResolution
  defdelegate list_identities(ingredient_id), to: IdentityResolution
  defdelegate verified_identity(ingredient_id), to: IdentityResolution
  defdelegate add_synonym(attrs), to: IdentityResolution
  defdelegate list_synonyms(scientific_identity_id), to: IdentityResolution
  defdelegate list_synonyms_for_ingredient(ingredient_id), to: IdentityResolution
  defdelegate verify_identity(identity_id, user_id \\ nil), to: IdentityResolution
  defdelegate reject_identity(identity_id, user_id \\ nil), to: IdentityResolution
  defdelegate list_pending_verification(opts \\ []), to: IdentityResolution
  defdelegate latest_identity_resolution_run(), to: IdentityResolutionRuns, as: :latest_run

  # ── Compounds (scientific facts) ───────────────────────────────────────

  defdelegate create_compound(attrs), to: Compounds
  defdelegate upsert_compound(attrs), to: Compounds
  defdelegate enrich_compound(compound, attrs), to: Compounds
  defdelegate get_compound!(id), to: Compounds
  defdelegate get_compound_by_name(name), to: Compounds
  defdelegate get_compound_by_identifier(namespace, identifier), to: Compounds
  defdelegate upsert_compound_identifier(attrs), to: Compounds
  defdelegate list_compound_identifiers(compound_id), to: Compounds
  defdelegate list_compounds(), to: Compounds
  defdelegate list_compounds_by_type(compound_type), to: Compounds
  defdelegate link_compound(attrs), to: Compounds
  defdelegate upsert_compound_relationship(attrs), to: Compounds
  defdelegate delete_compound_relationship(relationship), to: Compounds
  defdelegate list_compounds_for_ingredient(ingredient_id), to: Compounds
  defdelegate list_positive_compounds_for_ingredient(ingredient_id), to: Compounds
  defdelegate list_ingredients_for_compound(compound_id), to: Compounds
  defdelegate list_compound_relationships(ingredient_id), to: Compounds
  defdelegate add_compound_to_ingredient(ingredient_id, compound_attrs, rel_attrs), to: Compounds

  # ── Compound measurements (immutable quantitative facts) ───────────────────

  defdelegate create_measurement(attrs), to: CompoundMeasurements
  defdelegate record_measurement(attrs), to: CompoundMeasurements
  defdelegate get_measurement!(id), to: CompoundMeasurements
  defdelegate list_measurements_for_ingredient(ingredient_id), to: CompoundMeasurements
  defdelegate list_measurements_for_compound(compound_id), to: CompoundMeasurements
  defdelegate list_measurements_for_study(study_id), to: CompoundMeasurements
  defdelegate list_measurements(ingredient_id, compound_id), to: CompoundMeasurements

  # ── Evidence aggregation (read-only summaries of measurements) ─────────────

  defdelegate summarize(ingredient_id, compound_id), to: EvidenceAggregation
  defdelegate summarize_for_ingredient(ingredient_id), to: EvidenceAggregation

  # ── Compound candidates (derived → curated relationship pipeline) ──────────

  defdelegate enqueue_candidate_derivation(), to: CompoundCandidates
  defdelegate derive_candidate(ingredient_id, compound_id), to: CompoundCandidates
  defdelegate derive_candidates_batch(offset, limit), to: CompoundCandidates
  defdelegate score_candidate(ingredient_id, compound_id), to: CompoundCandidates
  defdelegate evidence_pairs(), to: CompoundCandidates
  defdelegate count_evidence_pairs(), to: CompoundCandidates
  defdelegate promote_candidate(candidate), to: CompoundCandidates
  defdelegate reject_candidate(candidate), to: CompoundCandidates
  defdelegate import_manual_candidate(ingredient_id, compound_id, attrs), to: CompoundCandidates
  defdelegate list_pending_candidates(opts \\ []), to: CompoundCandidates
  defdelegate list_candidates_for_ingredient(ingredient_id), to: CompoundCandidates
  defdelegate get_candidate!(id), to: CompoundCandidates
  defdelegate candidate_derivation_progress(), to: CompoundCandidates
end
