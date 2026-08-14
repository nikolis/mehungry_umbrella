# Language

Table `languages` · Schema `Mehungry.Languages.Language` (`lib/mehungry/languages/language.ex`).
Index: [`entities.md`](entities.md). Context: [`../localization.md`](../localization.md).

The set of supported languages (e.g. `En`, `El`). **Its primary key is `name`** (a
string), not an integer id.

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | **`@primary_key`** (`autogenerate: false`); required; unique |

## Relationships

Referenced across the app by **string FK on `name`** (`references: :name`), not an
integer id — including [Recipe](recipe.md) (`language_name`) and every `*Translation`
table (recipe, ingredient, category, unit, nutrient, species translations).

## Referenced by

[`recipe.md`](recipe.md) · [`../localization.md`](../localization.md) · every translation entity
