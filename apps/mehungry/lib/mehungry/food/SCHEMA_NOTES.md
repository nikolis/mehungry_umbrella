# Food Schemas — Review Notes

Notes from a read-through of `apps/mehungry/lib/mehungry/food/schemas/*` (branch `food_details_optimization`). These are things to revisit — nothing has been changed.

## Schema map

### Core recipe graph
- **`recipe.ex`** — the hub. Rich schema (title, times, difficulty, `nutrients` map, `ingredient_interactions` array, servings, image URLs). `has_many` recipe_ingredients (`on_replace: :delete`), recipe_hashtags (`on_replace: :nilify`), annotations, comments; `embeds_many :steps`; `has_one :post`; belongs to `User` and `Language` (keyed by `name` string). `get_hashtags/1` preprocesses hashtag titles to existing IDs before casting.
- **`recipe_ingredient.ex`** — join between recipe / ingredient / measurement_unit. Virtual `delete`/`temp_id` for LiveView form add/remove, `maybe_mark_for_deletion/1`.
- **`recipe_hashtag.ex`** — join to `Mehungry.Hashtag`, virtual `temp_id`, same deletion pattern.
- **`step.ex`** — embedded (no table), virtual `delete`/`temp_id`, self-marks `:delete` action.
- **`annotation.ex`** / **`like.ex`** — user↔recipe engagement (both carry an `:at` integer field).

### Ingredient / nutrition graph
- **`ingredient.ex`** — USDA fields (`food_class`, `nutrient_conversion_factors`, `publication_date`, `nutrient_data_source`) plus a derived `search_name` populated via `update_search_name/1` + public `normalize_string/1`. `has_many` portions, nutrients, translations.
- **`ingredient_nutrient.ex`** — ingredient↔nutrient amounts (median / amount / data_points / type_).
- **`ingredient_portion.ex`** — ingredient↔measurement_unit with `gram_weight`.
- **`nutrient.ex`** — USDA-derived (rank, number, reference_id, family); unique on `[:name, :measurement_unit_id]`.

### Reference / lookup + i18n
- **`category.ex`** / **`measurement_unit.ex`** — lookups with `has_many` translations.
- **`*_translation.ex`** (category, ingredient, measurement_unit) — all `belongs_to :language` keyed by `references: :name` (string FK `language_name`), consistent with `recipe.ex`.
- **`food_restriction_type.ex`** — standalone lookup (title / alias).

## Things to revisit

1. **`recipe_ingredient.ex:38-41`** — four `foreign_key_constraint` calls on non-existent names (`:name`, `:recipe_ingredients_name_fkey`, `:recipe_ingredients_name`, `:recipe_ingredients`) that are dead no-ops. Candidates for removal.

2. **`ingredient.ex:56-59`** — the `ingredient_nutrients` `cast_assoc` reuses `:ingredient_translation_sort` / `:ingredient_translation_drop` as its sort/drop params (copy-paste from the translation `cast_assoc` above). Likely a bug if sort/drop are ever used on nutrients.

3. **`category_translation.ex:24` / `ingredient_translation.ex:34`** — `unique_constraint(:name)` on the translation `name`. Suspicious: would block two ingredients/categories sharing a translated name across languages. Verify against the actual DB index before trusting.
