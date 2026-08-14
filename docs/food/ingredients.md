# Ingredients

The Ingredient model, its nutrient/portion children, and the search layer. Overview:
[`food.md`](food.md). Canonical schema: [Ingredient entity](../entities/ingredient.md)
(with IngredientNutrient, IngredientPortion folded in).

Schema: `Mehungry.Food.Ingredient` (`food/schemas/ingredient.ex`). Context:
`Mehungry.Food.Ingredients` (`food/ingredients.ex`).

## Schema

Fields, relationships, and constraints are the canonical
[Ingredient entity card](../entities/ingredient.md) (with **IngredientNutrient** and
**IngredientPortion** folded in). This doc covers the behavior around that schema.

### Names: global vs per-user

The two partial unique indexes
([entity card → Constraints](../entities/ingredient.md#constraints)) back the two
visibility scopes — `ingredients_global_name_index` (unique `name` where
`user_id IS NULL`) and `ingredients_user_name_index` (unique `[user_id, name]`). So a
user can create a private "olive oil" without colliding with the global one; visibility
scoping itself lives in the **search layer**, not the schema.

### `search_name`

`update_search_name/1` recomputes `search_name` from `name` on every change via the
public `Ingredient.normalize_string/1` (downcase → strip non-alphanumerics to spaces →
collapse whitespace). It feeds the trigram/prefix search paths.

### What the changeset does *not* touch

The **scientific enrichment** associations (`scientific_properties`,
`classifications`, `health_attributes`, `compound_relationships`) are deliberately
**not** in `cast_assoc` — they're written only via `Mehungry.Food.Enrichment`, never by
the USDA ingestion/reconciliation path (which replaces rows with its own
`delete_all` + create). `ingredient_portions`/`ingredient_nutrients`/`translation`
*are* cast (with `sort_param`/`drop_param`) for the admin form.

## Children

Both child tables are canonical in the entity cards — **IngredientNutrient**
([Ingredient → Nutrients](../entities/ingredient.md#nutrients)) holds the per-100g
amounts that are the basis of recipe nutrition ([`nutrients.md`](nutrients.md));
**IngredientPortion** ([Ingredient → Portions](../entities/ingredient.md#portions)) ties
the ingredient to a unit + `gram_weight`
([`measurement_units_and_portions.md`](measurement_units_and_portions.md)).

## `Food.Ingredients` — key functions

| Function | Notes |
|---|---|
| `get_ingredient/1` · `get_ingredient!/1` · `get_ingredient_details!/1` | By id; `_details` preloads the graph |
| `get_ingredient_by_{name,slug,translation_name}/*` | Alternate lookups |
| `create_ingredient/1` · `create_user_ingredient/*` | Global vs private-user creation |
| `create_ingredient_nutrient/1` · `create_ingredient_portion/1` | Child creation |
| `list_ingredients_paginated{,_translated}/*` | Paginated + localized listings |
| `list_recipe_ingredients/1` · `find_ri_allias/2` | Recipe-side helpers (`find_ri_allias` misspelling kept) |
| `delete_ingredients_without_nutrients/0` · `delete_branded_ingredients/*` | Large cascading cleanups |
| `enqueue_ingredient_backfill/*` · `reconciliation_progress/*` | Backfill/reconciliation |

## Search

There are two search implementations, each with a distinct job — they are **not**
interchangeable:

**`Mehungry.Food.IngredientSearch`** (`food/ingredient_search.ex`) — the ranked
prefix+fuzzy engine and the **single path for all user-facing ingredient name
search** (create-recipe & calendar pickers, shopping basket, bot setups, and the AI
`RecipeAgent`/`recipe_generator`/agent resolvers):

- `search/1` — ranked candidates for a plain name.
- `search_for_select/*` — shaped for select components.
- `search_in_language/*` — translated search.

**`Food.IngredientQueries`** owns everything else search-related: the full-text
`search_ingredient*` family (now serving the **admin** ingredient listing —
pagination cursor + total count + data-type filters + Branded-inclusive mode, which
`IngredientSearch` doesn't provide), plus `search_recipe/2` (→ `Search.RecipeSearch`),
`search_recipes_by_ingredient/1` (which itself calls `IngredientSearch.search`),
hashtag search, and `pagenate_query/1` (misspelling kept).

### Why both survive

`IngredientQueries` can't be deleted — it uniquely provides admin
pagination/count/data-type filtering and the recipe/hashtag searches.
`IngredientSearch` is the better fit for type-as-you-go pickers (prefix + typo-
tolerant fuzzy fallback). So the split is now **by role, not duplicated**: user
name-search was unified onto `IngredientSearch`; the FTS engine is admin-only. The
old user-facing FTS wrapper `search_ingredient_alt/3` (and the `exclude_branded/1`
helper it alone used) has been **removed** now that nothing calls it —
`search_ingredient_alt_admin/3` keeps its own copy of the FTS builder path.

### Shared query scopes

Both paths compose `Food.IngredientScope` (`food/ingredient_scope.ex`) so visibility
and filtering stay identical everywhere:

- `filter_by_owner/2` — global rows (`user_id IS NULL`) always; plus the viewer's
  own private rows and their friends' (`visible_owner_ids/1` via `Mehungry.Friends`).
- `maybe_filter_by_classes/2` — restrict to USDA food classes.
- `second_layer_category_ids/0` + `exclude_secondary_categories/3` — hide the
  composite/prepared "second layer" USDA categories (Snacks, Beverages, Baked
  Products, …) from **every** user-facing search, but never the viewer's own private
  ingredients. `IngredientSearch` previously left these visible; unifying on it
  applied the hide consistently across all pickers.

These helpers were previously copy-pasted into each module. `IngredientQueries`
re-exports `maybe_filter_by_classes/2` and `get_second_layer_foods_ids/0` via
`defdelegate` so the `Mehungry.Food` facade and its in-module callers are unaffected.
The dead legacy `search_ingredient2/1` and `search_ingredient3/1` (hard-coded
category-id exclusions, no callers) were removed along with their facade delegates.

Full write-up — the two implementations compared, ranking details, and every
caller across the codebase: [`ingredient_search.md`](ingredient_search.md).

## Related

- Measurement units & portions: [`measurement_units_and_portions.md`](measurement_units_and_portions.md)
- Nutrients: [`nutrients.md`](nutrients.md)
- AI ingredient creation (USDA-first, AI-estimated fallback): [`../ai/ai.md`](../ai/ai.md)
- Compound facts hanging off ingredients: [`../science/food_compounds.md`](../science/food_compounds.md)
- Schema review notes: `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md`
