# Nutrient

Table `nutrients` · Schema `Mehungry.Food.Nutrient` (`food/schemas/nutrient.ex`).
Index: [`entities.md`](entities.md). Model + helpers: [`../food/nutrients.md`](../food/nutrients.md).

USDA-derived reference data for a single nutrient (Energy, Protein, Iron, …).

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | required |
| `alternate_name`, `description` | string | |
| `family` | string | grouping (e.g. fats, vitamins) |
| `rank` | integer | **required** — USDA display rank |
| `number` | string | USDA nutrient number |
| `reference_id` | integer | |

## Relationships

- `belongs_to :measurement_unit` → [MeasurementUnit](measurement_unit.md) — the unit the
  amount is expressed in (g, mg, µg, kcal)
- `has_many :translations` (NutrientTranslation)
- Per-ingredient amounts live on `IngredientNutrient` — see [Ingredient → Nutrients](ingredient.md#nutrients)

## Constraints

- Unique `[:name, :measurement_unit_id]` — the same name can exist under different units.
- Required: `name`, `rank`.

## Referenced by

[`../food/nutrients.md`](../food/nutrients.md) · [`../food/nutrition_calculation.md`](../food/nutrition_calculation.md) · [`ingredient.md`](ingredient.md)
