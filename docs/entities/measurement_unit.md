# MeasurementUnit

Table `measurement_units` · Schema `Mehungry.Food.MeasurementUnit`
(`food/schemas/measurement_unit.ex`). Index: [`entities.md`](entities.md).
Model: [`../food/measurement_units_and_portions.md`](../food/measurement_units_and_portions.md).

A shared unit of measure (cup, tablespoon, gram, …) referenced by many ingredients
through [ingredient portions](ingredient.md#portions).

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | required; unique |
| `alternate_name` | string | |
| `url` | string | |
| `ndb_number` | string | USDA NDB number preserved when a numeric-named unit is reconciled to a real name |

## Relationships

- `has_many :ingredient_portions` — the [Ingredient](ingredient.md#portions) ↔ unit
  bridge (each carries a `gram_weight`)
- `has_many :translation` (MeasurementUnitTranslation)
- Referenced by recipe rows via `RecipeIngredient` — see [Recipe → Ingredients](recipe.md#ingredients)

## Constraints / notes

- Unique `name`.
- USDA imports can create junk **numeric-named** units; `Food.Measurements` provides
  detection, `reconcile_measurement_unit/2`, and purge helpers — see
  [`../food/measurement_units_and_portions.md`](../food/measurement_units_and_portions.md).
- The gram unit is looked up by literal name (a legacy naming artifact — see
  [`../ai/ai_agents.md`](../ai/ai_agents.md)).

## Referenced by

[`../food/measurement_units_and_portions.md`](../food/measurement_units_and_portions.md) · [`recipe.md`](recipe.md) · [`ingredient.md`](ingredient.md) · [`nutrient.md`](nutrient.md)
