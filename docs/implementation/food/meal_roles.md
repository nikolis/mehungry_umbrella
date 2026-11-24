# Recipe meal roles

What part a recipe plays in a real meal — a **main**, a **side**, a **meze**, a
**breakfast** dish… Each recipe can hold **several** roles (spanakopita is a main,
a side, a meze and a snack). The AI meal planner reads them so a dip or a meze is
never served as somebody's whole dinner.

**Why it exists:** before this, nothing in the data said what a dish *is*. The
planner saw only a title, difficulty, servings and calories, so a recipe like
"Patlıcan Salatası" (a smoky eggplant meze) could be placed as a complete lunch or
dinner. See [`../ai/meal_plan.md`](../ai/meal_plan.md).

## Vocabulary — `Mehungry.Food.MealRoles`

A **fixed list in code** (`food/meal_roles.ex`), not admin-editable. The planner's
logic depends on specific roles (`main`, `soup`, `dinner`), so the names have to stay stable.
Adding a role is a code change.

| role | meaning | fills |
|---|---|---|
| `breakfast` | a breakfast dish | Breakfast |
| `main` | a complete lunch/dinner on its own | Lunch, Dinner |
| `dinner` | an evening-only complete meal, too light for a midday main (omelette, light fish plate) | Dinner |
| `soup` | a soup that can be the meal (fasolada, avgolemono) | Lunch, Dinner |
| `salad` | a salad (accompaniment) | — |
| `side` | a side dish | — |
| `meze` | meze / appetizer / dip / shared small plate | — |
| `snack` | a between-meal snack | Morning/Afternoon Snack |
| `dessert` | a dessert or sweet | Morning/Afternoon Snack |
| `drink` | a drink or smoothie | Morning/Afternoon Snack |
| `pre_workout` | fuel before training: easy to digest, carb-led, low fat/fibre | — (tag) |
| `post_workout` | recovery after training: protein-rich with carbs | — (tag) |
| `component` | a building block: sauce, dressing, dough, stock | never planned |

`pre_workout` / `post_workout` are **tags on top of a dish's normal roles** — the
planner has no workout slot, so on their own they fill nothing; a pre-workout
snack is `snack` + `pre_workout`. Adding a role needs **no migration** (`role` is
a plain string validated against `MealRoles.all/0`); recipes classified before
the role existed only pick it up via **Reclassify unreviewed** (or by hand).

- `slot_roles/1` maps a planner slot label ("Dinner") or a canonical meal type
  ("dinner") to the roles that may fill it.
- `fits_slot?/2` returns true when any of a recipe's roles is accepted for the
  slot. **An unclassified recipe (no roles) always fits**, so the planner keeps
  working for recipes the classifier hasn't reached yet.

## Data model

- **`recipe_meal_roles`** (`Food.RecipeMealRole`) — one row per (recipe, role),
  unique on `(recipe_id, role)`.
  - `source`: `ai` | `manual`
  - `confidence`: 0..1, nil for manual rows
  - `reviewed` + `reviewed_by_id` + `reviewed_at`
- **`recipes.meal_roles_classified_at`** — set when the classifier has *attempted*
  the recipe, even if it returned nothing. A backfill run therefore always moves
  forward and never re-fetches the same recipe.
- **`recipe_meal_role_runs`** (`Food.RecipeMealRoleRun`) — one tracking row per
  admin "Classify" click (`mode`, `status`, `processed`/`total`) for the live
  progress bar.

Migration: `20261120140000_create_recipe_meal_roles.exs`. Entity card:
[`../entities/recipe.md`](../entities/recipe.md).

## Writing roles — `Food.MealRoleAssignments`

**A human decision always wins.**

- `apply_ai_roles/2` writes the classifier's output for a recipe.
  - It never touches a recipe with any reviewed role.
  - Otherwise it replaces the recipe's unreviewed rows.
  - It **auto-confirms** when every role has confidence ≥ 0.85.
  - It stamps `meal_roles_classified_at`, even for an empty result.
- `set_recipe_roles/3` is the admin's explicit set. It adds new roles as
  `manual`, removes the rest, and marks everything reviewed.
- `confirm_recipe/2` / `confirm_many/2` accept the current set as is.
- `reset_and_classify/1` is the admin "Reclassify" button. It drops all of the
  recipe's rows, reviewed ones included, and asks the AI again.

Reads:
- `roles_for/1` → `%{recipe_id => [role]}`, batched; used by the planner.
- `list_for_review/2` and `coverage/0` back the admin page.

Facade delegates on `Mehungry.Food`: `meal_roles_for/1`,
`set_recipe_meal_roles/3`, `confirm_recipe_meal_roles/2`,
`confirm_many_recipe_meal_roles/2`, `list_recipes_for_meal_role_review/2`,
`meal_role_coverage/0`, `enqueue_meal_role_classification/1`,
`reclassify_recipe_meal_roles/1`.

## Classifier — `AI.RecipeMealRoleClassifier`

- Same shape as `AI.TaxonomyClassifier`: one JSON prompt through `AI.Client`,
  Haiku 4.5 by default (`:meal_role_classifier_model` overrides it).
- It runs in batches of 20. For each recipe it sends the title, a 300-character
  description excerpt, cuisine, servings, up to 12 ingredient names, per-serving
  kcal + protein (from `NutrientUtils.macro_summary/1`, the calendar's own math)
  and the total time (`MealRoleAssignments.classifier_inputs/1`).
- The prompt asks it to judge from ingredients and portion size, not just the
  title, since titles can be Greek, Turkish, etc. It includes worked examples
  (Patlıcan Salatası → meze + side).
- Only IDs from the batch and roles in the vocabulary survive parsing.
- **Behaviour seam:** `:meal_role_classifier`, stubbed in tests by
  `AI.RecipeMealRoleClassifierStub`.

## Triggers — `ObanWorkers.RecipeMealRoleClassificationWorker`

- **On every recipe create/update** (`Food.Recipes`, next to the hashtag +
  nutrient hooks): `maybe_classify_on_save/1` enqueues a single-recipe job.
  - It runs on the `:default` queue, unique per recipe for 60 s, and is skipped
    when a human already reviewed the roles.
  - Every create path goes through it: manual, AI bot, and the MyPlate/
    Gutenberg/UniTools importers.
- **Admin backfill** (`enqueue_classification/1`, one run at a time):
  - `"unclassified"` — recipes never attempted.
  - `"unreviewed"` — recipes with no reviewed role that haven't been attempted
    since the run started.
  - It runs on `:ai_agents` and self-re-enqueues batch by batch (the
    TaxonomyClassificationWorker pattern), broadcasting progress on the
    `"recipe_meal_roles"` PubSub topic.
  - A classifier error marks the run `failed`.

## Admin UI — `/professional/recipe-meal-roles`

`ProfessionalLive.RecipeMealRoles` (admin-only, `:default2`). Linked from the
admin sidebar ("Meal roles") and `/professional/recipes`.

- **Header:**
  - Coverage: recipes / classified / needs review / reviewed.
  - A per-role count strip; click a role to filter. Low `main` counts mean the
    catalog is thin for lunches/dinners.
  - **Classify unclassified** and **Reclassify unreviewed** buttons, with live
    progress.
- **Tabs:** Needs review (lowest AI confidence first) · Unclassified · Reviewed ·
  All.
- **Filters:** title search, role, source (in-app / MyPlate / Gutenberg /
  UniTools), include private.
- **Each row:**
  - Thumbnail, title (opens the recipe), cuisine, kcal + protein per serving,
    source and owner.
  - **All role chips** (one per vocabulary role). Click to add or remove; any number can be on.
    Chips show the AI confidence, a ✓ when reviewed, amber when confidence is
    below 0.6, dashed for an unsaved addition, struck through for an unsaved
    removal.
  - Actions:
    - **Save** stores the edited set.
    - **Discard** drops unsaved edits.
    - **Confirm** accepts the AI's set.
    - **Reclassify** asks the AI again; the row refreshes when the job reports
      back.
- **Bulk:** select rows, then **Confirm selected**.

## How the meal planner uses them (`AI.Agents.MealPlanCore`)

1. The recipe search tool takes an optional **`slot`**. `RecipeVectorSearch`'s
   `:meal_roles` option filters **in SQL, before the limit** to recipes that
   either hold an accepted role or have no roles at all.
2. Every search result carries `roles`. Recipes whose only role is `component`
   are never offered.
3. `submit_plan` rejects a meal's **main** recipe whose known roles don't fit its
   slot (`MealPlanCore.Rules`), with a message telling the model to search with
   that slot. Ingredient items and unclassified recipes pass. A Lunch may add a
   `salad` / `dessert` **part** (searched with `part:`), which must carry that role.
4. Both agents' prompts define each slot in terms of roles: lunch/dinner must be
   a main or a meal soup (dinner may also be a `dinner` dish), and breakfast must be a breakfast dish.

The API is unchanged: no `/api/v1` shape changed.

## Eval

- `MealPlanScorer` has a `slot_roles` check, a **hard rule** (`:fail` on any
  misfit).
- `MealPlanCatalog` seeds roles on every fixture recipe, plus a meze bait,
  "Smoky Eggplant Meze Dip Dinner".
- The balanced-week scenario asserts `slot_roles` never fails.

## Rollout

1. Deploy and run the migration. The planner behaves as before for unclassified
   recipes.
2. On `/professional/recipe-meal-roles`, press **Classify unclassified**. The cost
   is roughly $0.01 per 20 recipes on Haiku.
3. Work the **Needs review** queue. Watch the per-role counts for thin coverage of
   `main` and `breakfast`.

## Tests

- `test/mehungry/food/meal_roles_test.exs`
- `test/mehungry/food/meal_role_assignments_test.exs`
- `test/mehungry/oban_workers/recipe_meal_role_classification_worker_test.exs`
- `test/mehungry/ai/agents/meal_plan_slot_roles_test.exs`
- `mehungry_web/test/mehungry_web/live/recipe_meal_roles_test.exs`
