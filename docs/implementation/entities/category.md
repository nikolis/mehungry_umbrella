# Category

Table `categories` · Schema `Mehungry.Food.Category` (`food/schemas/category.ex`).
Index: [`entities.md`](entities.md). Context: `Food.Categories`.

A food category lookup that classifies ingredients (USDA food groups).

## Fields

| Field | Type | Notes |
|---|---|---|
| `name` | string | required; unique |
| `description` | string | |
| `usda_code` | string | USDA food-group code |

## Relationships

- `has_many :category_translation` (CategoryTranslation)
- Referenced by [Ingredient](ingredient.md) via `belongs_to :category` (required)

## Constraints

- Unique `name`.

## Referenced by

[`ingredient.md`](ingredient.md) · [`../food/food.md`](../food/food.md)
