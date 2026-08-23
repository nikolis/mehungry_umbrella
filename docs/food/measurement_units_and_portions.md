# Measurement Units & Portions

How quantities are expressed: the `MeasurementUnit` lookup, the `IngredientPortion`
bridge that ties an ingredient + unit to a gram weight, and how a recipe ingredient
resolves to one or the other. Overview: [`food.md`](food.md). Canonical schema:
[MeasurementUnit](../entities/measurement_unit.md) · portions on
[Ingredient → Portions](../entities/ingredient.md#portions).

Schemas: `Food.MeasurementUnit`, `Food.IngredientPortion` (`food/schemas/`).
Context: `Food.Measurements` (`food/measurements.ex`).

## MeasurementUnit

Fields, relationships, and constraints are the canonical
[MeasurementUnit entity card](../entities/measurement_unit.md). Units are a shared
lookup — the same unit ("cup", "tablespoon", grams) is referenced by many ingredients
through portions. The behavior below is the numeric-name cleanup/repair surface.

### Numeric-named units & reconciliation

USDA imports can create junk, **numeric-named** units (a bare NDB number instead of a
real name). `Food.Measurements` provides the cleanup/repair surface:

- Detection: `numeric_measurement_unit_name?/1`, `real_unit_name?/1`,
  `list_numeric_named_measurement_units/0`, `count_numeric_named_measurement_units/0`.
- Repair: `reconcile_measurement_unit/2` — renames a numeric unit to its real food
  description, preserving the original in `ndb_number`; `start_reconciliation_run/*`
  drives it in bulk (tracked by `measurement_unit_reconciliation_runs`).
- Purge: `delete_measurement_unit_if_unreferenced/1`, `purge_junk_measurement_unit/1`,
  `purge_all_junk_measurement_units/0`, `delete_numeric_named_measurement_units/0`.

## IngredientPortion — the bridge

The ingredient ↔ unit bridge; its fields and constraints (`gram_weight` required, the
`validate_has_unit_or_description/1` rule, nullable unit) are canonical on the
[Ingredient entity card → Portions](../entities/ingredient.md#portions). The role it
plays here is behavioral: `gram_weight` is the **conversion factor** — it turns "2 cups
of flour" into grams, which is what the nutrition engine consumes (per-100g
`IngredientNutrient` amounts × grams). See [`nutrition_calculation.md`](nutrition_calculation.md).

A portion carries a free-text `description` (USDA `portionDescription`) instead of a unit
when there is **no** real measurement unit; `IngredientPortion.display_name/1` prefers
that `description`, else the linked unit's `name`.
`Food.Measurements.get_measurement_unit_portions_for_ingredient(s)/1` returns the valid
`(unit, portion, gram_weight)` options for an ingredient — used by the AI agent's
`search_ingredient` tool and the recipe form's unit picker.

## How a recipe ingredient picks a unit

A `RecipeIngredient` row resolves to **exactly one** of:

1. a **measurement unit** — grams (no portion), or a unit-bearing portion; or
2. a **description-only portion** — a USDA portion with no unit (e.g. "1 medium banana").

The recipe form collapses this into a single virtual integer, `unit_selection`:

| `unit_selection` | Means | `changeset/2` sets |
|---|---|---|
| `>= 0` | a `measurement_unit_id` | `measurement_unit_id = sel`, `ingredient_portion_id = nil` |
| `< 0` | `-ingredient_portion_id` (description-only) | `ingredient_portion_id = -sel`, `measurement_unit_id = nil` |

For unit-bearing rows, `ingredient_portion_id` is then **re-derived at save time** from
`(ingredient_id, measurement_unit_id)` via `prepare_changes/2` (`maybe_resolve_ingredient_portion/1`),
so it only touches the DB at insert/update — not on every form re-render. Grams (and any
unit with no matching portion) resolve to a `nil` portion, which the nutrition engine
reads as "the quantity is already grams".

`RecipeIngredient.unit_selection_value/1` produces the dropdown's selected value for a
persisted row (the `-portion_id` encoding for description-only portions, else the
`measurement_unit_id`), and `unit_label/1` renders a nil-tolerant label (unit name →
portion description → `"g"`).

## `Food.Measurements` — key functions

| Function | Notes |
|---|---|
| `list_measurement_units/0` · `get_measurement_unit!/1` · `get_measurement_unit_by_name/1` | Lookups |
| `search_measurement_unit/*` | Unit search |
| `create/update/delete_measurement_unit/*` · `change_measurement_unit/*` | CRUD |
| `get_measurement_unit_portions_for_ingredient(s)/1` | Valid unit/portion options per ingredient |
| reconciliation + junk-purge family | See "Numeric-named units" above |

## Related

- Recipe ingredients & the aggregate: [`recipes.md`](recipes.md)
- Ingredient portions in context: [`ingredients.md`](ingredients.md)
- Turning portions into nutrition: [`nutrition_calculation.md`](nutrition_calculation.md)
- Unit translations: [`../localization.md`](../localization.md)
