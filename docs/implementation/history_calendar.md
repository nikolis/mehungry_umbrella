# Calendar / Meal Tracker (`Mehungry.History`)

The consumer **weekly meal calendar** and self-tracking loop: the day/slot grid, the
three kinds of logged food, per-day notes, the consumed-portion history, and the
denormalization that makes per-day nutrition fast. This is the surface a client lives
in against their nutritionist's plan, and the one `features/normal_user.md` calls the
act-2 headline. Backed by the `Mehungry.History` context and
`MehungryWeb.CalendarLive` (`/calendar`).

> Nutrition **math** (how a meal's numbers are computed/scaled/summed) is
> [`food/nutrition_calculation.md`](food/nutrition_calculation.md); AI week-planning is
> [`ai/meal_plan.md`](ai/meal_plan.md). This doc is the **data model + calendar
> behavior** those two feed into.

---

## The model — one meal, three food kinds

A **`UserMeal`** (`history_user_meals`) is one slot on one day for one user:
`start_dt`/`end_dt` (naive UTC), `title`, `meal_type`, `user_id`, and a nullable
`blueprint_plan_id` (set when the meal was laid down by importing a `BlueprintPlan` —
see [`features/meal_blueprints.md`](features/meal_blueprints.md), `on_delete: :nilify_all`).
It owns three independent child collections (all `on_replace: :delete`), so a single
meal can mix a recipe, a DB ingredient, and an off-database food:

| Child (table) | What it logs | Key fields |
|---|---|---|
| **`RecipeUserMeal`** (`history_recipe_user_meals`) | a recipe from the catalog | `recipe_id`, `cooking_portions`, `consume_portions`, `cooking` |
| **`IngredientUserMeal`** (`history_ingredient_user_meals`) | a whole-food ingredient already in the DB | `ingredient_id`, `quantity`, resolved `measurement_unit_id`/`ingredient_portion_id`, virtual `unit_selection`, **denormalized `nutrients` map** |
| **`FreeFoodUserMeal`** (`history_free_food_user_meals`) | an **arbitrary food not in our DB** (e.g. fast food) | `name`, `grams` (resolved total), `nutrients_per_100g` (client-supplied), optional `portion_name`/`portion_grams`/`portions` |

**Meal-type vocabulary** is the single source `Mehungry.History.MealType`:
`breakfast, morning_snack, lunch, afternoon_snack, dinner` (ordered), plus **`nil` = the
"Unsorted" bucket, shown last**. `label/1` maps unknown/`nil` → `"Unsorted"`. This list
is drift-guarded against `AiBotConfig.meal_types/0` by a test and is reused by
`MealBlueprints` and the mobile API's `meal_type_vocabulary` (spec §9).

### `ConsumeRecipeUserMeal` — "I actually ate N portions"

A recipe meal can be *planned* (on the calendar) and separately *consumed* (eaten). The
`consume_recipe_user_meals` table records a consumption event (its own
`start_dt`/`end_dt` + `consume_portions`). The day's nutrition scales a recipe meal by
`consume_portions / servings` — so a logged-but-unconsumed recipe can contribute 0, and
an imported blueprint meal is seeded `consume_portions: 1` precisely so the summary
shows real numbers (see [`features/meal_blueprints.md`](features/meal_blueprints.md)).

### `DayNote` — per-day free text

`history_day_notes` (`date`, `body` ≤ 2000 chars, `user_id`) via
`get_day_note/2` · `list_day_notes/2` · `upsert_day_note/3`. The per-day journalling
half of the self-tracker.

---

## The denormalization decision (why per-day nutrition is fast)

Per-day/-week nutrition sums **stored** numbers, never recomputed from ingredients at
read time:

- **Recipes** carry their full `recipe.nutrients` tree, computed once at write time by
  `RecipePutNutrientsWorker` (see [`food/nutrition_calculation.md`](food/nutrition_calculation.md)).
- **Logged ingredients** carry their own denormalized `ingredient_user_meals.nutrients`,
  **written at log time** (`put_ingredient_user_meal_nutrients/_`) so the aggregator
  doesn't re-derive a tree per row on every calendar render. A one-time backfill exists
  for pre-denormalization rows: `History.start_ingredient_nutrient_backfill/0` (run once
  after deploy — see memory *Calendar Performance*).
- **Free foods** are scaled from their client-supplied `nutrients_per_100g × grams/100`
  into the same tree shape via `scaled_free_food_nutrient_tree/_`.

All three resolve to the **same structured nutrient tree a recipe has**
(`NutrientCalculation.ingredient_nutrient_tree/2` for ingredients), so the day summary
(`NutrientUtils.summarize_meals_nutrients/1`) treats a logged food identically to the
same food inside a recipe — one aggregation path, no divergent copies (the REST↔LiveView
parity rule). `format_user_meals/1` is the shared shaping step both the calendar
LiveView and the mobile API (`GET /meals/day/:date/nutrition`) call.

## Week-scoped loading (performance)

The calendar loads **only the viewed week**, not a user's whole history:
`list_calendar_user_meals/3` (and `list_user_meals_in_range/_`) are date-range-scoped.
Combined with the denormalized nutrients above, a week render is a bounded query + an
in-memory sum rather than an N-recipe recomputation. See memory *Calendar Performance*.

---

## Context API (`Mehungry.History`)

- **Read:** `list_calendar_user_meals/3` (week-scoped, the calendar's main read),
  `list_user_meals_in_range/_`, `get_user_meal!/1` (+ `_raw!`), `format_user_meals/1`
  (shaping + nutrition), `get_available_portions_for_user_meal/_`.
- **Write:** `create_user_meal/1`, `update_user_meal/2`, `delete_user_meal/1`,
  `delete_user_meals_in_date_range/_`, `duplicate_user_meal/_` ("copy a meal to today"),
  `change_user_meal/_`.
- **Nutrition helpers:** `put_ingredient_user_meal_nutrients/_`,
  `scaled_ingredient_nutrient_tree/2`, `scaled_free_food_nutrient_tree/_`,
  `start_ingredient_nutrient_backfill/0`.
- **Day notes:** `get_day_note/2`, `list_day_notes/2`, `upsert_day_note/3`.

## Calendar LiveView features (`CalendarLive`, `/calendar`)

Beyond the grid + add/edit/delete meal form, the self-tracker shipped (see memory
*Calendar Self-Tracker Roadmap*):

- **Per-day notes** (`DayNote`), **copy-a-meal-to-today** (`duplicate_user_meal`).
- **Personal avoid-list** — `UserProfile.avoid_foods`; meals whose foods match a term are
  flagged via `MealPlanAgent.matched_avoid_terms` (distinct from a blueprint's
  *generation-time* avoid enforcement in [`ai/meal_plan.md`](ai/meal_plan.md)).
- **Day-summary badges** — sodium / saturated-fat warnings computed from the day's
  summed tree.
- **Plan a week with AI** (quota-gated) → [`ai/meal_plan.md`](ai/meal_plan.md).
- **Follow/unfollow a blueprint** + import a `BlueprintPlan` onto the week
  (`blueprint_plan_id` stamp).

## Two outward hand-offs

The calendar is the source for two adjacent features that each deserve (and currently
lack — see `architecture_audit_2026-10-27.md`) their own doc:

- **Shopping list for the week** → `Inventory.create_basket_for_range/4` (re-opens the
  week's existing list via `get_basket_for_week/2` rather than duplicating). One click on
  the calendar → `/basket?basket_id=`.
- **Weekly-plan share card + feed post** → a deterministic SVG share card + a
  `WEEKLY_PLAN` `Post`, with macro parity via `NutrientUtils.macro_summary/1` (backed by
  `PublishedPlans`; see memory *Weekly-Plan Share Card + Post*).

## Mobile API

The whole calendar is mirrored under `/api/v1/meals*` — see
[`new_dec_specs/mobile_api_spec.md`](new_dec_specs/mobile_api_spec.md) §9, including the
`free_food_user_meals` / `ingredient_user_meals` logging contracts and the shared
`GET /meals/day/:date/nutrition` aggregation.

## Related

- [`food/nutrition_calculation.md`](food/nutrition_calculation.md) — the nutrient math + the aggregation path this doc feeds.
- [`ai/meal_plan.md`](ai/meal_plan.md) — AI week generation that materializes `UserMeal`s.
- [`features/meal_blueprints.md`](features/meal_blueprints.md) — `BlueprintPlan` → calendar import (`blueprint_plan_id`).
- `features/normal_user.md` — the consumer-facing description of this surface.
