# Ingredient

Table `ingredients` · Schema `Mehungry.Food.Ingredient` (`food/schemas/ingredient.ex`).
Index: [`entities.md`](entities.md). Behavior: [`../food/ingredients.md`](../food/ingredients.md).

A food ingredient — USDA-backed in the shared catalog, or a private user-created one.

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | required |
| `description`, `url` | string | |
| `search_name` | string | derived from `name` via `normalize_string/1`; feeds trigram/prefix search |
| `food_class`, `data_type`, `nutrient_data_source`, `publication_date` | string | USDA provenance |
| `fdc_id`, `ndb_number` | integer | USDA identifiers |
| `nutrient_conversion_factors` | array\<map\> | USDA |
| `version` | integer | default `0`; monotonic reconciliation counter |

## Relationships

- `belongs_to :category` → [Category](category.md), `belongs_to :measurement_unit` → [MeasurementUnit](measurement_unit.md)
- `belongs_to :user` → [User](user.md) — **NULL = shared/global catalog**, set = private user ingredient
- `has_many :ingredient_translation`
- Curated onto a species via [FoundementalFood](foundemental_food_species.md#foundementalfood) → [FoundementalFoodSpecies](foundemental_food_species.md)
- **Science sidecar (read-only, not cast):** `scientific_properties`, `classifications`,
  `health_attributes`, `compound_relationships`/`compounds`, `study_links`/`studies` —
  written only via `Food.Enrichment`. See [`../science/food_compounds.md`](../science/food_compounds.md).

### Nutrients

`has_many :ingredient_nutrients` *(on_replace: :delete)* — the join
`Mehungry.Food.IngredientNutrient` (`food/schemas/ingredient_nutrient.ex`) holds the
**per-100g** amount of one [Nutrient](nutrient.md) in this ingredient: `amount` (required,
per-100g), `median`, `data_points`, `type_`. This is the raw material the nutrition
engine scales by grams — see [`../food/nutrition_calculation.md`](../food/nutrition_calculation.md).

### Portions

`has_many :ingredient_portions` *(on_replace: :delete)* — the bridge
`Mehungry.Food.IngredientPortion` (`food/schemas/ingredient_portion.ex`) ties this
ingredient + a [MeasurementUnit](measurement_unit.md) to a **`gram_weight`** (required) —
the conversion factor that turns "2 cups" into grams. A portion may instead carry a
free-text `description` (USDA `portionDescription`) when it has **no** real unit
(measureUnit "undetermined"/id 9999); it must have `gram_weight` and at least one of
`measurement_unit_id`/`description`. `display_name/1` prefers `description`, else the
unit name. Full model: [`../food/measurement_units_and_portions.md`](../food/measurement_units_and_portions.md).

## Constraints

- Two partial unique indexes: `ingredients_global_name_index` (unique `name` where
  `user_id IS NULL`) and `ingredients_user_name_index` (unique `[user_id, name]`).
- Required: `name`, `category_id`.

## Referenced by

[`../food/ingredients.md`](../food/ingredients.md) · [`../food/nutrition_calculation.md`](../food/nutrition_calculation.md) · [`foundemental_food_species.md`](foundemental_food_species.md) · [`../ai/ai.md`](../ai/ai.md)
