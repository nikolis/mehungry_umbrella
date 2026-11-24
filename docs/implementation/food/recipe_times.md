# Recipe times (prep + cook) and their AI backfill

**Status:** shipped 2026-11-24 (Phase 1 of the meal-plan composition rules); the time
rules are **enforced** by both meal-plan agents since Phase 3 (search caps in SQL +
`submit_plan` check).

## Why
The AI meal planner's composition rules are time-based: **Breakfast** takes a recipe
of at most 15 minutes, a weeknight **Dinner** at most 40 (a `dinner`-role dish is
exempt). A recipe whose time is unknown is **excluded** from those slots rather than
guessed — so recipes saved without a time (common for imports) need one. This page
covers the one definition of "total time", the search filter that uses it, and the AI
sweep that fills missing times.

## Total time — one definition
`Food.total_time_minutes/1` (`Food.Recipes`) = `preperation_time_lower_limit` +
`cooking_time_lower_limit` (the fields the recipe form edits), **nil when neither is
set**. Shared by:

- `MehungryWeb.RecipeSEO` (schema.org `totalTime`);
- `RecipeVectorSearch.search/2`, whose SQL repeats the same expression
  (`NULLIF(COALESCE(prep,0) + COALESCE(cook,0), 0)`):
  - every result carries `total_minutes`;
  - `max_total_minutes: n` keeps only recipes with a **known** total ≤ n;
  - `time_exempt_roles: [..]` keeps a recipe holding one of those meal roles whatever
    its time (Dinner: `["dinner"]`).

## AI backfill — `Food.RecipeTimeEstimation`
- **Pending** = no time at all (prep and cook both empty/zero) **and**
  `recipes.times_estimated_at` is nil.
- `AI.RecipeTimeEstimator` (Haiku, one JSON prompt per batch of 20, behind the
  `:recipe_time_estimator` config seam; stubbed in tests by
  `Mehungry.AI.RecipeTimeEstimatorStub`) estimates `prep` and `cook` minutes from the
  title, servings, ingredients and steps.
- `apply_estimate/2` writes **only empty fields** (a typed time is never overwritten),
  caps values at 24 h, always stamps `times_estimated_at` (so a recipe the model
  skipped is never retried and a run always ends), and drops the recipe from
  `:recipes_cache`.
- Runs follow the [Oban-UI-connected pattern](../../reference_architecture/oban_ui_connected_worker.md):
  `recipe_time_estimation_runs` row (`RecipeTimeEstimationRun`,
  `pending → processing → completed | failed`, `processed`/`total`), the
  self-re-enqueueing `ObanWorkers.RecipeTimeEstimationWorker` on `:ai_agents`, and
  `{:recipe_time_run, run}` broadcasts on the `"recipe_time_estimation"` topic. One run
  at a time (`{:error, :already_running}`); nothing to do → `{:error, :nothing_pending}`.
- Facade: `Food.recipe_time_coverage/0` (`%{total, with_time, missing,
  attempted_without}`), `Food.enqueue_recipe_time_estimation/0`.

## Admin page
`/professional/recipe-times` (`ProfessionalLive.RecipeTimes`, `:default2`, sidebar
"Recipe times"): coverage counts, **Estimate missing times (N)**, and the last run's
live progress bar. Recipes the AI could not time are counted separately; fix those by
hand in the recipe editor.

## Runbook
After deploy: open the page and run **Estimate missing times** once; re-run after a
bulk import.
