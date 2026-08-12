# Recipe Nutrition Calculation

How a recipe's nutrient totals are produced, stored, read, and aggregated across
the app. There are **three families of paths**:

1. **Write / calculation path** — the authoritative computation, run once and
   persisted onto the recipe (`NutrientCalculation`).
2. **Read / display paths** — everything that renders the *stored* totals
   (`recipe.nutrients`); no recalculation happens here.
3. **Aggregation paths** — the calendar / meal-plan layer that sums stored
   recipe totals into per-day / per-week / per-meal figures.

A separate, mostly-superseded **legacy on-the-fly path** (`RecipeUtils`) still
lingers in a few calendar helpers — see the last section.

---

## The core model

Nutrients are **computed once at write time and cached on the recipe row**, not
recomputed on read. The `recipes` table stores
(`apps/mehungry/lib/mehungry/food/schemas/recipe.ex`):

| Column | Meaning |
|---|---|
| `nutrients` (`:map`, jsonb, default `%{}`) | Name → nutrient map (hierarchical, with `children`), the recipe's full totals |
| `primary_nutrients_size` (`:integer`) | How many leading entries are "primary" (currently always `8`) for display grouping |

Nutrient-interaction warnings are **not** stored on the recipe. They are derived
on read from the recipe's ingredients — see the interactions section below. (A
former `ingredient_interactions` column was dropped: it was only ever populated
from the recipe's *top-level* nutrient map, which never surfaces the individual
vitamins/minerals the rules key on, so it was always empty.)

USDA stores every nutrient **per 100 g**; the calculation scales each ingredient
by `total_grams / 100` and sums. Full math is documented in the moduledoc of
`apps/mehungry/lib/mehungry/food/nutrition/nutrient_calculation.ex`.

---

## 1. Write / calculation path (authoritative)

Module: **`Mehungry.Food.NutrientCalculation`**
(`apps/mehungry/lib/mehungry/food/nutrition/nutrient_calculation.ex`).

### Trigger points (everything that enqueues a recompute)

All recipe writes funnel through **`Mehungry.RecipePutNutrientsWorker`** (Oban,
`default` queue) — nutrient calculation is **asynchronous**, never inline with the
HTTP request.

| Entry point | File:line | Enqueues |
|---|---|---|
| `Recipes.create_recipe/1` | `food/recipes.ex:457` | one worker per new recipe |
| `Recipes.update_recipe/2` | `food/recipes.ex:497` | one worker per edit |
| `Nutrients.enqueue_nutrient_recalculation_for_all/0` | `food/nutrients.ex:49` | untracked batch over all recipes |
| `Nutrients.start_full_recalculation_run/0` | `food/nutrients.ex:68` | tracked batch (carries `run_id`, reports progress via `NutrientRecalculationRuns`) |
| Admin UI: `/professional/recipes` → `"recompute_nutrients"` | `professional_live/recipes.ex:46` | calls `start_full_recalculation_run/0` |
| Spoonacular import → `Food.create_recipe` | `food_data/spoonacular_importer.ex:51` | via create_recipe |
| AI bot `DailyRecipeGenerationWorker` → `Food.create_recipe` | `oban_workers/daily_recipe_generation_worker.ex:117` | via create_recipe |

### Worker → persistence

`RecipePutNutrientsWorker.perform/1`
(`apps/mehungry/lib/mehungry/oban_workers/recipe_put_nutrients_worker.ex`):

1. Loads + preloads the recipe (`recipe_ingredients: [:measurement_unit, :ingredient]`, etc.).
2. `Food.change_recipe(recipe)` → base changeset.
3. Also (re)creates the social post + invalidates `:recipes_cache`.
4. **`Food.put_nutrient_info(changeset, Map.from_struct(recipe))`** — the calculation hook.
5. `Repo.update/1` persists `nutrients` / `primary_nutrients_size` / `ingredient_interactions`.
6. On tracked runs, reports success/failure to `NutrientRecalculationRuns`.

`Food.put_nutrient_info/2` (`food/recipes.ex:529`, delegated from `food.ex:59`):

- Calls **`NutrientCalculation.calculate_recipe_nutrition_value(attrs)`** → `{primary_size, nutrients}`.
- Folds the nutrient list into a name-keyed map and `put_change`s `:nutrients`
  and `:primary_nutrients_size`.
- If the nutrient list is empty, leaves the changeset unchanged (logs a warning).

### The calculation itself (`NutrientCalculation`)

`calculate_recipe_nutrition_value/1` (`nutrient_calculation.ex:63`) →

1. **`map_ingredients_to_structured_form/1`** (`:155`) — bulk-loads each ingredient
   with `:ingredient_portions` and `ingredient_nutrients: [nutrient: :measurement_unit]`,
   then per recipe-ingredient computes:
   - **`calculate_gram_weight/5`** (`:216`) — resolves `quantity` → grams:
     1. gram-family unit (`g`/`gram`/`grammar`, alt name `g`) → quantity is already grams;
     2. else the recipe-ingredient's own `ingredient_portion_id` (authoritative, also
        resolves description-only portions with nil `measurement_unit_id`);
     3. else the ingredient's `IngredientPortion` matching `measurement_unit_id`;
     4. `grams_per_unit = portion.gram_weight / portion.amount` (amount default 1.0);
     5. unresolved → logs a warning and contributes **0 g**.
   - **`build_nutrient_list/2`** (`:266`) — scales each nutrient by `gram_weight / 100`,
     after **`filter_energy_duplicates/1`** (`:322`) collapses USDA's multiple Energy
     rows to one (Atwater Specific > Atwater General > kcal > first) to avoid 3–4× calorie inflation.
2. **`calculate_nutrition_for_recipe/1`** (`:370`) — flattens all per-ingredient nutrients,
   groups by **`NutrientNameNormalizer.normalize/1`**, sums, builds the tree via
   **`NutrientHierarchyBuilder.build_hierarchy/1`**, sorts via `sort_nutrients_by_priority/1`
   (Energy→Protein→Total Fat→Vitamins→Carbs→Fiber→Sugars→Minerals→rest).
3. Returns `{8, structured_nutrients}` (or `{0, []}` for no ingredients).

### Pre-save validation

`NutrientCalculation.validate_ingredient_units/1` (`:86`) surfaces ingredient/unit
pairs lacking an `IngredientPortion` as changeset errors. Wired into both
create and update via `validate_ingredient_units_in_changeset/1` (`food/recipes.ex:573`,
called at `:444` and `:483`) so calculation never silently drops grams later.

Supporting modules (all under `food/nutrition/`):
`NutrientNameNormalizer`, `NutrientHierarchyBuilder`, `NutrientMerger`,
`NutrientInteractions`, plus `IngredientPortion` + `ingredient_nutrients` schemas.

---

## 2. Read / display paths (render stored `recipe.nutrients`)

None of these recalculate — they read the persisted map and render it through the
shared accordion. Entry component:
**`MehungryWeb.RecipeComponents.recipe_nutrients/1`**
(`components/recipe_components.ex:736`) → **`MehungryWeb.NutritionAccordion.nutrition_accordion`**
(`components/nutrition_accordion.ex`).

Call sites that feed `recipe.nutrients` / `primary_nutrients_size` to the display:

| Surface | File:line |
|---|---|
| Recipe details tab | `recipe_details_live/recipe_details_component.ex:334`; `components/recipe_details_tabs_config.ex:28`; `components/tabs_component.ex:66` |
| Recipe browser | `recipe_browser_live/index.ex:502` |
| Profile (own recipes) | `profile_live/index.ex:141` |
| Landing page | `landing_live.ex:495` (list filtered by non-empty `nutrients` at `:61`) |
| AI bot review | `professional_live/ai_bot_live/recipe_review.ex:523` |
| Calendar meal cards | `calendar_live/calendar/widget.ex:837,844` (per-recipe stored `recipe_nutrients`) |
| Nutritionist client calendar | `nutritionist_live/client_calendar.ex:241` |

---

## 3. Aggregation paths (calendar / meal plans)

These sum **stored** recipe totals across meals into day/week/meal figures.

Primary aggregator: **`Mehungry.NutrientUtils.summarize_meals_nutrients/1`**
(`apps/mehungry/lib/mehungry/nutrient_utils.ex:558`, aliased `Nu`):
- For each meal, pulls each `recipe_user_meal.recipe_nutrients`, **scales by the
  consumed fraction** (`scale_nutrient_map/consumed_fraction`), adds ingredient-meal
  nutrients, then `merge_nutrients_with_normalization/1` + `sort_nutrients_for_display/1`.

Callers (all in `calendar_live/calendar/widget.ex`): day chart (`:19`), meal-type
chart (`:559`), week chart (`:586`), grouped view (`:607`); results also drive
`calendar_live/calendar/pie_chart.ex`.

> **Single implementation (reconciled).** A second, divergent
> `Mehungry.Food.NutrientMerger.summarize_meals_nutrients/1` used to exist. It
> had **no callers**, returned a sorted *list* (not the `name => nutrient` map
> the calendar needs), and — critically — **never scaled by the consumed
> portion** (no `consumed_fraction/1`), so it would have over-reported logged
> nutrition. It was deleted; `NutrientUtils.summarize_meals_nutrients/1` is the
> single canonical summariser. `NutrientMerger` keeps only its shared
> name/key primitives (`normalize_nutrient_name/1`, `to_string_keys/1`,
> `to_atom_keys/1`). Its old second hierarchy builder (`merge_nutrients/1`,
> `build_hierarchy_simple/1`, `normalize_units/1`, …) duplicated
> `NutrientHierarchyBuilder`, silently dropped fat subcategories, and had no
> production callers — it was removed.

---

## 4. `RecipeUtils` — two surviving display helpers

Module: **`Mehungry.Food.RecipeUtils`** (`apps/mehungry/lib/mehungry/food/recipe_utils.ex`).

This module used to hold an **older on-the-fly calculation** that recomputed a
recipe's nutrients from `recipe_ingredients` on every read (`get_nutrients/1`,
`calculate_recipe_nutrition_value/1`, `calculate_nutrition_for_recipe_ingredient*/1`,
`adjust_amount/4`, `get_nutrient_category/3`, `calculate_recipe_ingredient_categories_array/1`,
…). That whole path was **dead** — superseded by the write-time
`NutrientCalculation` — and had a latent bug (`adjust_amount/4` multiplied by
`portion.gram_weight` **without** dividing by `portion.amount`). It has been
**removed**. Its only external dependant, the historical migration
`20241002130246_add_nutrition_meta_to_recipes`, was simplified to a schema-only
migration (the `nutrients` columns are populated by `RecipePutNutrientsWorker` /
`start_full_recalculation_run/0`, not by app code called from a migration).

What remains are the **two view-only helpers** the calendar still uses on an
*already-computed* `recipe.nutrients` map:
- `RecipeUtils.sort_nutrients_from_db/1` — calendar widget `:93`; floats headline
  nutrients to the top of a `{name, nutrient}` list and indexes it.
- `RecipeUtils.reform_nutrients/1` — calendar widget `:864`; re-keys a stored
  ingredient recipe's `nutrients` map (string keys, unit struct → unit name) for a
  meal card.

---

## Nutrient interactions (derived on read)

Interaction warnings (e.g. "Vitamin C boosts iron absorption") are **not** stored
on the recipe — they are computed from the recipe's ingredients when displayed,
via **`Food.get_interactions_for_recipe/1`** (`food/nutrients.ex`) →
**`NutrientInteractions.interactions_for_ingredients/1`**, which classifies each
ingredient's significant nutrients directly from `ingredient_nutrients`. This is
the same path the food-detail page uses (`Food.get_interactions_for_ingredients/1`),
so both surfaces share one implementation.

`get_interactions_for_recipe/1` reads `recipe.recipe_ingredients` (must be
preloaded) and returns `[]` when it isn't. The recipe's hierarchical
`nutrients` map is **not** used for interactions: the rules key on individual
vitamins/minerals that live nested as `children`, so a top-level scan of that
map can't see them. Rendered by the interaction component in `core_components.ex`.

## Related but distinct: ingredient-level (per-100g) display

These read `ingredient.ingredient_nutrients` **directly** (USDA per-100g values) and
are **not** recipe totals — listed to avoid confusion:

- `food_detail_live/index.ex:71` `build_top_nutrients/1` (food detail page, per 100g).
- `shopping_basket_live/index.ex:406` (maps ingredient nutrients into a food payload).
- `condition_detail_live/index.ex:81` / `species_detail_live` `top_nutrients_for/1`.

---

## Quick reference: the one canonical flow

```
create_recipe / update_recipe / recompute run
        │  (enqueue Oban)
        ▼
RecipePutNutrientsWorker.perform
        │
        ▼
Food.put_nutrient_info(changeset, recipe)
        │
        ▼
NutrientCalculation.calculate_recipe_nutrition_value
   map_ingredients_to_structured_form
     └ calculate_gram_weight  (quantity → grams)
     └ build_nutrient_list    (× grams/100, dedupe Energy)
   calculate_nutrition_for_recipe
     └ normalize + hierarchy + priority sort
        │
        ▼
Repo.update → recipes.nutrients (jsonb)
        │
        ▼  (read only, no recompute)
RecipeComponents.recipe_nutrients → NutritionAccordion   (display)
NutrientUtils.summarize_meals_nutrients                  (calendar aggregation)
```

---

## Test coverage

| Suite | File | Covers |
|---|---|---|
| `NutrientCalculationTest` | `test/mehungry/food/nutrition/nutrient_calculation_test.exs` | `calculate_gram_weight/5` (gram unit, portion-by-id, portion-by-unit, `amount` divisor, nil amount, string quantity, missing-portion → 0 g), `build_nutrient_list/2` scaling + unit fallback, `filter_energy_duplicates/1` (Atwater Specific/General/kcal precedence), `calculate_nutrition_for_recipe/1` aggregation + priority sort, `calculate_total_calories/1`, `sort_nutrients_by_priority/1`, `safe_to_float/1`, `safe_nutrient_amount/1`, `get_value/2`, `calculate_recipe_nutrition_value/1` guards, and DB-backed `validate_ingredient_units/1` |
| `NutrientUtilsTest` | `test/mehungry/nutrient_utils_test.exs` | `to_grams/2`, `macronutrient?/1`, `consumed_fraction/1`, `scale_nutrient_map/2`, `summarize_meals_nutrients/1` (portion scaling, recipe+ingredient merge, synonym normalization, empty), `normalize_nutrient_name/1`, `merge_nutrients_with_normalization/1`, `macro_bucket/1`, `macro_totals/1`, `sort_nutrients_for_display/1`, `macro_buckets/0` |
| `NutrientMergerTest` | `test/mehungry/food/nutrition/nutrient_merger_test.exs` | `normalize_nutrient_name/1`, `to_string_keys/1` ↔ `to_atom_keys/1` |
| `RecipeUtilsTest` | `test/mehungry/food/recipe_utils_test.exs` | the two surviving helpers: `sort_nutrients_from_db/1`, `reform_nutrients/1` |
| `NutrientTest` | `test/mehungry/nutrient_test.exs` | end-to-end `calculate_recipe_nutrition_value/1` over seeded USDA data |

Run them all:

```bash
mix test apps/mehungry/test/mehungry/food/nutrition/ \
         apps/mehungry/test/mehungry/nutrient_utils_test.exs \
         apps/mehungry/test/mehungry/nutrient_test.exs
```
