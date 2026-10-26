# Recipe

Table `recipes` · Schema `Mehungry.Food.Recipe` (`food/schemas/recipe.ex`).
Index: [`entities.md`](entities.md). Behavior/context: [`../food/recipes.md`](../food/recipes.md).

The hub of the food model — a user-authored recipe with steps, ingredients, hashtags,
and a computed nutrition map.

## Fields

| Field | Type | Notes |
|---|---|---|
| `title` | string | required; unique per user (`title_user_index`) |
| `description` | string | free text (may carry `#hashtags` appended by AI) |
| `author`, `cousine` | string | |
| `servings` | integer | |
| `difficulty` | integer | default `1` (1=easy, 2=medium, 3=hard) |
| `cooking_time_{lower,upper}_limit` | integer | minutes; `lower` required |
| `preperation_time_{lower,upper}_limit` | integer | minutes; `lower` required *(spelling kept)* |
| `private` | boolean | |
| `list_image_url`, `image_url`, `detail_image_url`, `recipe_image_remote`, `original_url` | string | |
| `primary_nutrients_size` | integer | |
| `nutrients` | map | **computed & stored** — see [`../food/nutrition_calculation.md`](../food/nutrition_calculation.md) |
| `condition_flags` | array\<map\> | **virtual**; filled at display by `MehungryWeb.RecipeFlags` for opted-in users: `%{condition, compound, recommendation, severity}` |

## Relationships

- `belongs_to :user` → [User](user.md)
- `belongs_to :language` → [Language](language.md) (**FK by `name`**, field `language_name`)
- `has_one :post` · `has_many :comments`, `:annotations`, `:user_recipes`

### Steps

`embeds_many :steps` — `Mehungry.Food.Step` (`food/schemas/step.ex`) is embedded, so
steps live inline in the `recipes` row (no table). Fields: `title`, `description`
(required — the step text; AI folds an optional `tip` into it), `index` (required —
order), plus virtual `delete`/`temp_id` for LiveView add/remove (a step self-marks
`action: :delete`).

### Ingredients

`has_many :recipe_ingredients` *(on_replace: :delete)* — the join
`Mehungry.Food.RecipeIngredient` (`food/schemas/recipe_ingredient.ex`) links a recipe
to an [Ingredient](ingredient.md) at a `quantity`, resolved to **either** a
[MeasurementUnit](measurement_unit.md) **or** a description-only ingredient portion
*(see [Ingredient → Portions](ingredient.md#portions))*:

- Fields: `quantity` (required), `ingredient_allias` *(spelling kept)*, virtual
  `unit_selection` (form-only: `>=0` → `measurement_unit_id`, `<0` →
  `-ingredient_portion_id`), virtual `delete`/`temp_id`.
- `belongs_to :recipe`, `:ingredient` (required), `:measurement_unit` (nullable),
  `:ingredient_portion` (nullable).
- `changeset/2` splits `unit_selection` into the real FKs, then re-derives
  `ingredient_portion_id` from `(ingredient_id, measurement_unit_id)` via
  `prepare_changes/2` at save (grams / no match → nil portion = "already grams").
  Full model in [`../food/measurement_units_and_portions.md`](../food/measurement_units_and_portions.md).
- Helpers: `unit_selection_value/1`, `unit_label/1` (unit name → portion description → `"g"`).
- *Note:* four `foreign_key_constraint` calls on non-existent names are dead no-ops
  (`SCHEMA_NOTES.md`).

### Hashtags

`has_many :recipe_hashtags` *(on_replace: :nilify)* — the join
`Mehungry.Food.RecipeHashtag` (`food/schemas/recipe_hashtag.ex`) links a recipe to a
[Hashtag](hashtag.md) (virtual `temp_id`). `Recipe.changeset/2` pre-resolves incoming
hashtags to existing `hashtag_id`s (`get_hashtags/1`) so duplicates reuse a tag.

## Constraints

- Unique `title_user_index` on `(title, user_id)`.
- Required: `title`, `language_name`, `user_id`, `cooking_time_lower_limit`,
  `preperation_time_lower_limit`; `recipe_ingredients` is `cast_assoc(required: true)`.

## Referenced by

[`../food/recipes.md`](../food/recipes.md) · [`../food/nutrition_calculation.md`](../food/nutrition_calculation.md) · [`../ai/ai.md`](../ai/ai.md)
