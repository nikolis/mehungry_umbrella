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

`Mehungry.Food.IngredientSearch` (`food/ingredient_search.ex`) is the ranked
prefix+fuzzy DB search used throughout (the AI `RecipeAgent`, setup seed ingredients,
etc.):

- `search/1` — ranked candidates for a plain name.
- `search_for_select/*` — shaped for select components.
- `search_in_language/*` — translated search.

`Food.IngredientQueries` owns the broader `search_ingredient*` family (full-text,
trigram, admin, translated variants), `search_recipe/2` (→ `Search.RecipeSearch`),
hashtag search, and `pagenate_query/1` (misspelling kept).

## Related

- Measurement units & portions: [`measurement_units_and_portions.md`](measurement_units_and_portions.md)
- Nutrients: [`nutrients.md`](nutrients.md)
- AI ingredient creation (USDA-first, AI-estimated fallback): [`../ai/ai.md`](../ai/ai.md)
- Compound facts hanging off ingredients: [`../science/food_compounds.md`](../science/food_compounds.md)
- Schema review notes: `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md`
