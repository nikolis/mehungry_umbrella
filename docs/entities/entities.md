# Entities — Data Dictionary

Canonical, one-card-per-entity reference for the app's **fundamental entities** — the
primary domain nouns of the food model plus the cross-cutting entities everything hangs
off (User, Language, Hashtag). Each card is the single source of truth for that entity's
table, fields, relationships, and constraints; other docs **link here** instead of
re-describing the schema.

**Fundamental only.** Join / child / embedded tables (RecipeIngredient, Step,
RecipeHashtag, IngredientNutrient, IngredientPortion, FoundementalFood) are **not**
their own cards — each is documented *inside* the parent entity it relates, as the
relationship it expresses (see the "expresses" column).

Schemas live under `apps/mehungry/lib/mehungry/food/schemas/` unless noted. Behavior
and context (not repeated here) live in the domain docs: [`../food/food.md`](../food/food.md),
[`../science/science.md`](../science/science.md), [`../users/accounts.md`](../users/accounts.md).

## Food model

| Entity | Table | Card | Expresses (folded-in joins/children) |
|---|---|---|---|
| **Recipe** | `recipes` | [`recipe.md`](recipe.md) | Step (embedded); Recipe↔Ingredient (RecipeIngredient); Recipe↔Hashtag (RecipeHashtag) |
| **Ingredient** | `ingredients` | [`ingredient.md`](ingredient.md) | Ingredient↔Nutrient (IngredientNutrient); Ingredient↔Unit (IngredientPortion) |
| **MeasurementUnit** | `measurement_units` | [`measurement_unit.md`](measurement_unit.md) | — |
| **Nutrient** | `nutrients` | [`nutrient.md`](nutrient.md) | — |
| **Category** | `categories` | [`category.md`](category.md) | — |
| **FoundementalFoodSpecies** | `foundemental_food_species` | [`foundemental_food_species.md`](foundemental_food_species.md) | Species↔Ingredient (FoundementalFood) |

## Cross-cutting

| Entity | Table | Card | Expresses |
|---|---|---|---|
| **Hashtag** | `hashtags` | [`hashtag.md`](hashtag.md) | — |
| **User** | `users` | [`user.md`](user.md) | — |
| **Language** | `languages` | [`language.md`](language.md) | string-FK (`name`) target of every translatable entity |

## Conventions across these entities

- **Language FK by name.** Translatable entities (`Recipe`, and the `*Translation`
  tables) reference `Language` by `references: :name` (a string FK), not an integer id —
  see [`language.md`](language.md).
- **Form virtuals.** Child rows edited in LiveView forms carry virtual
  `delete`/`temp_id` fields and self-mark `action: :delete` (Step, RecipeIngredient,
  RecipeHashtag).
- **USDA provenance.** Ingredient/Nutrient/Portion carry USDA-derived fields
  (`fdc_id`, `rank`, `number`, `gram_weight`, `nutrient_data_source`, …).
- **Schema review notes** (dead constraints, copy-paste params) live next to the code:
  `apps/mehungry/lib/mehungry/food/SCHEMA_NOTES.md`.
