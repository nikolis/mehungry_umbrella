# Food Domain — Overview

The core food model: recipes, ingredients, nutrients, measurement units and
portions, plus the reference/lookup and localization data around them. This is the
front door to `docs/food/` — each section links to the doc that covers it in depth.

`Mehungry.Food` is a permanent **defdelegate facade**; the implementation lives in
sub-modules under `apps/mehungry/lib/mehungry/food/`. New code may call sub-modules
directly, but every public function stays reachable through the facade.

> **Entity schemas** (tables, fields, relationships, constraints) are the canonical
> [entities data dictionary](../entities/entities.md) — [Recipe](../entities/recipe.md),
> [Ingredient](../entities/ingredient.md), [MeasurementUnit](../entities/measurement_unit.md),
> [Nutrient](../entities/nutrient.md), [Category](../entities/category.md),
> [FoundementalFoodSpecies](../entities/foundemental_food_species.md). This doc covers
> behavior/context and links there instead of repeating field lists.

## What the domain owns

| Area | Sub-module | Deep dive |
|---|---|---|
| **Recipes** | `Food.Recipes` — CRUD, cached `get_recipe!/1,2`, hashtag extraction, nutrition enrichment on save, Oban enqueues | [`recipes.md`](recipes.md) |
| **Ingredients** | `Food.Ingredients` — CRUD + lookups (id/name/slug/translation), private user ingredients, portions & nutrients | [`ingredients.md`](ingredients.md) |
| **Ingredient search** | `Food.IngredientSearch` (ranked prefix+fuzzy) · `Food.IngredientQueries` (FTS/trigram/admin/translated) | [`ingredient_search.md`](ingredient_search.md) |
| **Measurement units & portions** | `Food.Measurements` — units, translations, the ingredient↔unit portion bridge, unit reconciliation | [`measurement_units_and_portions.md`](measurement_units_and_portions.md) |
| **Nutrients (data model)** | `Food.Nutrients` + `Food.Nutrition.*` helpers (merger, hierarchy, interactions, mapper) | [`nutrients.md`](nutrients.md) |
| **Nutrition calculation** | `Food.Nutrition.NutrientCalculation`, `RecipeUtils`, `RecipePutNutrientsWorker` | [`nutrition_calculation.md`](nutrition_calculation.md) |
| **Categories** | `Food.Categories` — category CRUD/search, food restriction types | this doc |
| **Localization** | `Food.Localization` — recipe/ingredient/category/unit translations, `localize_recipes/2` | [`../localization.md`](../localization.md) |
| **Engagement** | `Food.Engagement` — likes, recipe comments, annotations | this doc |
| **Bioactive compounds (sidecar)** | `Food.Compounds` etc. — facts only, no advice | [`../science/food_compounds.md`](../science/food_compounds.md) |

## The core recipe graph

```
Recipe ─┬─ embeds_many :steps                (Step, no table)
        ├─ has_many :recipe_ingredients ─────(RecipeIngredient)─┬─ belongs_to :ingredient
        │                                                       ├─ belongs_to :measurement_unit
        │                                                       └─ belongs_to :ingredient_portion
        ├─ has_many :recipe_hashtags ────────(RecipeHashtag → Hashtag)
        ├─ has_one  :post   · has_many :comments · :annotations
        └─ field    :nutrients (map)          ← computed, see nutrition_calculation.md

Ingredient ─┬─ has_many :ingredient_portions  (IngredientPortion: ingredient↔unit + gram_weight)
            ├─ has_many :ingredient_nutrients  (IngredientNutrient: per-100g amounts)
            └─ has_many :ingredient_translation
```

`RecipeIngredient` resolves to **either** a measurement unit (grams / a unit-bearing
portion) **or** a description-only USDA portion — see
[`measurement_units_and_portions.md`](measurement_units_and_portions.md).

## External sources & configuration

| Source | Used for | Client | Key |
|---|---|---|---|
| **USDA FoodData Central** | Ingredient search (basket flow) and AI ingredient creation | `FoodData.Usda.SearchClient` (Req) · `FoodData.Usda.FdcClient` (HTTPoison) | `FDC_API_KEY` (required, no fallback) |

Two USDA clients exist **deliberately** — different HTTP stack, retry, and parsing
semantics; the basket flow uses `SearchClient`, the AI recipe agent uses `FdcClient`.
Unifying them is a behavior change and was deferred.

## Internal collaborators

| Context | What Food uses it for | Doc |
|---|---|---|
| **Search** | `search_recipe/2` delegates to `Search.RecipeSearch` (FTS) | — |
| **Languages** | Recipe/ingredient/unit/category translations (FK by `name`) | [`../localization.md`](../localization.md) |
| **Accounts** | Recipe/ingredient ownership (`user_id`); private user ingredients | [`../users/accounts.md`](../users/accounts.md) |
| **AI** | `RecipeAgent` creates ingredients + recipes; embeddings; translation | [`../ai/ai.md`](../ai/ai.md) |
| **Science** | Compound facts hang off ingredients/species as a read-only sidecar | [`../science/science.md`](../science/science.md) |
| **Oban** | Nutrition recompute, embeddings, image, translation, reconciliation | — |

## Conventions & known quirks (kept on purpose)

- **Recipes cache** — `get_recipe!/1` reads/writes `:recipes_cache` under the
  **pinned** key `{Mehungry.Food, id}` (not `__MODULE__`), because
  `RecipePutNutrientsWorker` invalidates exactly that key. `update_recipe/2`
  refreshes it; `delete_recipe/1` relies on LRU + worker invalidation. Details in
  [`recipes.md`](recipes.md).
- **Misspelled public names kept** — `pagenate_query/1`, `find_ri_allias/2`,
  `get_user_category_rulles/1`, `Food.NutrientNameNormilizer` — call sites depend on
  them; renaming is churn for no behavior gain.
- **Two divergent `normalize_nutrient_name/1`** (`NutrientUtils` fuzzy-fallback vs
  `NutrientManager` capitalize-fallback) — cross-referenced in comments, not unified.
- **Schema review notes** live next to the code in
  `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md` (e.g. dead
  `foreign_key_constraint` no-ops on `recipe_ingredient`, a copy-paste sort/drop
  param on `ingredient.ingredient_nutrients`).

## Read next

- [`recipes.md`](recipes.md) — the Recipe aggregate: schema, steps, recipe-ingredients,
  hashtags, the cache, and nutrition enrichment on save.
- [`ingredients.md`](ingredients.md) — the Ingredient model (USDA fields, global vs
  per-user names, private ingredients), its nutrients/portions, and the search layer.
- [`measurement_units_and_portions.md`](measurement_units_and_portions.md) — units,
  portions, `gram_weight`, description-only portions, and unit reconciliation.
- [`nutrients.md`](nutrients.md) — the Nutrient data model and the `Food.Nutrition.*`
  helper modules (merge, hierarchy, interactions, display mapping).
- [`nutrition_calculation.md`](nutrition_calculation.md) — how a recipe's `nutrients`
  map is computed, stored, read, and aggregated.
