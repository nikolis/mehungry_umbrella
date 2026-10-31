# Nutrients

The `Nutrient` data model, per-ingredient amounts, and the `Food.Nutrition.*` helper
modules that name, merge, group, and relate nutrients. Overview: [`food.md`](food.md).
Canonical schema: [Nutrient entity](../entities/nutrient.md) · per-100g amounts on
[Ingredient → Nutrients](../entities/ingredient.md#nutrients).

This doc is the **data model + helpers**; how a recipe's `nutrients` map is actually
computed, stored, read, and aggregated is [`nutrition_calculation.md`](nutrition_calculation.md).

Schemas: `Food.Nutrient`, `Food.IngredientNutrient` (`food/schemas/`). Context:
`Food.Nutrients` (`food/nutrients.ex`). Helpers: `food/nutrition/`.

## Nutrient & IngredientNutrient — the schema

Both schemas are canonical in the entity cards: the [Nutrient](../entities/nutrient.md)
reference table (USDA `rank`/`number`/`family` driving display order/grouping, unique on
`[:name, :measurement_unit_id]`), and its per-100g amounts on
[Ingredient → Nutrients](../entities/ingredient.md#nutrients) (the `IngredientNutrient`
join: `amount` per-100g, `median`, `data_points`, `type_`).

That per-100g `amount` is the raw material of recipe nutrition — scaled by the grams a
recipe uses (via `IngredientPortion.gram_weight`) and summed. The calculation lives in
[`nutrition_calculation.md`](nutrition_calculation.md).

## `Food.Nutrients` — key functions

| Function | Notes |
|---|---|
| `list_nutrients/0` · `get_nutrient/1` · `create_nutrient/1` | CRUD/lookup |
| `list_key_nutrients/0` | The curated "key" nutrients surfaced in UI |
| `get_interactions_for_recipe/1` · `get_interactions_for_ingredients/1` | Derived nutrient interactions (see below) |
| `start_full_recalculation_run/*` · `enqueue_nutrient_recalculation_for_all/0` | Bulk recompute (tracked by `nutrient_recalculation_runs`) |
| `enqueue_interaction_recalculation_for_all/0` | Bulk interaction recompute |

## `Food.Nutrition.*` helpers

| Module | Does |
|---|---|
| **`NutrientCalculation`** | The authoritative per-recipe calculation — see [`nutrition_calculation.md`](nutrition_calculation.md) |
| **`NutrientMerger`** | Merges nutrient maps, normalizing keys (`normalize_nutrient_name/1`, `to_atom_keys`/`to_string_keys`) |
| **`NutrientHierarchyBuilder`** | `build_hierarchy/*` — nests nutrients into their display groups (e.g. fats → saturated/mono/poly) |
| **`NutrientInteractions`** | `interactions_for_ingredients/*` over a `rules/0` table — derived synergies/inhibitions (e.g. iron + vitamin C), computed **on read** |
| **`NutrientMapper`** | Display humanization — `get_nutrient_name/2`, `humanize_nutrient_name/1` (moved from the web app) |
| **`NutrientNameNormalizer`** | `normalize/1`, plus `is_fatty_acid?/1` / `get_fat_category/1` for fat grouping |

## Known quirks (kept on purpose)

- **`Food.NutrientNameNormilizer`** — module-name typo kept to avoid rename churn
  (distinct from `NutrientNameNormalizer` above; check the call site).
- **Two divergent `normalize_nutrient_name/1`** — `Mehungry.NutrientUtils`
  (fuzzy-fallback) vs `Food.NutrientManager` (capitalize-fallback). Cross-referenced in
  comments, intentionally not unified.
- Schema review notes (incl. a copy-paste `sort_param`/`drop_param` on
  `ingredient.ingredient_nutrients`) live in
  `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md`.

## Related

- The calculation/read/aggregation flow: [`nutrition_calculation.md`](nutrition_calculation.md)
- Where the per-100g amounts come from: [`ingredients.md`](ingredients.md)
- Grams conversion via portions: [`measurement_units_and_portions.md`](measurement_units_and_portions.md)
- Nutrient translations: [`../localization.md`](../localization.md)
