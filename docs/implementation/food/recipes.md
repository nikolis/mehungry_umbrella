# Recipes

The Recipe aggregate and the `Food.Recipes` context. Overview and links:
[`food.md`](food.md). Canonical schema: [Recipe entity](../entities/recipe.md)
(with Step, RecipeIngredient, RecipeHashtag folded in).

Schema: `Mehungry.Food.Recipe` (`food/schemas/recipe.ex`). Context:
`Mehungry.Food.Recipes` (`food/recipes.ex`), reachable via the `Mehungry.Food` facade.

## The aggregate

Schema — scalar fields, the computed `nutrients` map, virtual `condition_flags`,
`embeds_many :steps`, the `recipe_ingredients` / `recipe_hashtags` joins, the
`language` FK-by-name, relationships, and constraints — is the canonical
[Recipe entity card](../entities/recipe.md) (with **Step**, **RecipeIngredient**, and
**RecipeHashtag** folded in). What follows is the behavior the context layer adds on top.

### Recipe ingredients — unit resolution

A `RecipeIngredient` row resolves to *either* a measurement unit (grams or a
unit-bearing portion) *or* a description-only USDA portion. The form encodes the choice
in a single virtual `unit_selection` integer (positive → `measurement_unit_id`,
negative → `-ingredient_portion_id`), and `changeset/2` splits it back into the real
FKs and re-derives `ingredient_portion_id` via `prepare_changes/2` at save time. Full
model in [`measurement_units_and_portions.md`](measurement_units_and_portions.md).

`RecipeIngredient.unit_label/1` gives a nil-tolerant display label (unit name →
portion description → `"g"`), and is called by the social publishers on plain maps too.

### Hashtags

`Recipe.changeset/2` pre-processes incoming hashtags via `get_hashtags/1`, swapping a
`%{hashtag: %{title}}` for an existing `%{hashtag_id}` before casting so duplicates
reuse the existing tag.

## `Food.Recipes` — key functions

| Function | Notes |
|---|---|
| `create_recipe/1` · `update_recipe/2` | Persist + enrich nutrients (`put_nutrient_info/2`) and enqueue Oban work (embedding, image, nutrient recompute) |
| `get_recipe!/1,2` | **Cached** read (see below); the arity-2 form takes a language for localized reads |
| `get_recipe_no_caching!/1` | Bypasses the cache — used by workers that must not read/populate stale cache entries |
| `delete_recipe/1` · `delete_recipes_by_ids/1` | Deletes; cache handled by LRU + worker invalidation |
| `list_recipes/*` · `list_user_recipes/1` · `count_recipes*` | Listing/counting families |
| `list_*_without_ingredients` · `count_recipes_missing_embeddings` | Maintenance/backfill helpers |
| `put_nutrient_info/2` | Nutrition enrichment applied on save — see [`nutrition_calculation.md`](nutrition_calculation.md) |

## The recipes cache

`get_recipe!/1` reads/writes `:recipes_cache` (Cachex, LRU, limit 150) under the
**pinned** key `{Mehungry.Food, id}`. The namespace is written literally, **not**
`__MODULE__`, because `RecipePutNutrientsWorker` invalidates entries under exactly that
key after a nutrient recompute — a rename would silently break invalidation.

- `update_recipe/2` refreshes the cached entry.
- `delete_recipe/1` does **not** actively evict — LRU eviction plus the worker's
  targeted invalidation cover it.
- Workers use `get_recipe_no_caching!/1` so a background job never serves or seeds a
  stale struct.

## Nutrition on save

Creating/updating a recipe enriches its `nutrients` map and enqueues a recompute; the
authoritative write path, read/display paths, and calendar aggregation are documented
in [`nutrition_calculation.md`](nutrition_calculation.md).

## Related

- Search: `Food.search_recipe/2` → `Search.RecipeSearch` (full-text).
- AI generation persists recipes through this context — see [`../ai/ai.md`](../ai/ai.md).
- Schema review notes: `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md`.
