# The four "plan" contexts — which is which

Mehungry has **four** distinct context trees with "plan"/"meal" in the name, plus the AI
generator that writes into them. They are easy to confuse; this note draws the boundary so
you build on the right one. (Surfaced as an open question in
[`architecture_audit_2026-10-27.md`](architecture_audit_2026-10-27.md) §4.1.)

| Context | What it is | Table(s) | Status | Doc |
|---|---|---|---|---|
| **`History`** | The **live private calendar** — what a user actually logged, per day/slot | `history_user_meals` (+ recipe/ingredient/free-food children, day notes, consumes) | **current, flagship** | [`history_calendar.md`](history_calendar.md) |
| **`MealBlueprints`** | A reusable **targets template** (a "typical day": macro split + required/avoid nutrients/compounds/foods), optionally condition-scoped. Authored by nutritionists; generates `BlueprintPlan`s | `meal_blueprints*`, `meal_blueprint_plans*` | **current** | [`features/meal_blueprints.md`](features/meal_blueprints.md) |
| **`PublishedPlans`** | An **immutable public snapshot** of one calendar week, SEO-indexed at `/meal-plans/:slug` | `published_meal_plans` | **current** | [`published_plans.md`](published_plans.md) |
| **`Plans`** (`Mehungry.Plans`) | The **legacy** meal-plan tree (`MealPlan → DailyMealPlan → Meal`) | `meal_plans`, `daily_meal_plans`, `meals` | **legacy, still referenced** | — (this note) |

## How they relate

```
MealBlueprints (template)                 History (live calendar)        PublishedPlans (public snapshot)
  Blueprint → BlueprintPlan                 UserMeal + children             PublishedMealPlan
        │ import_plan_to_calendar/3                │ publish_week/3                 ▲
        └─────────────────────────────▶  UserMeal  ─────────────────────────────────┘
                                             ▲
             AI.MealPlanGenerator / MealPlanAgent  ──▶ materialize onto the calendar
                                                   └─▶ or store as a standalone BlueprintPlan
```

- **`AI.MealPlanGenerator` / `MealPlanAgent`** ([`ai/meal_plan.md`](ai/meal_plan.md)) is the
  *generator*, not a store: it returns normalized entries that land on the `History`
  calendar **or** are stored as a `MealBlueprints.BlueprintPlan`.
- `MealBlueprints` → `History` via `import_plan_to_calendar/3` (stamps
  `history_user_meals.blueprint_plan_id`).
- `History` → `PublishedPlans` via `publish_week/3` (snapshot).
- Async mobile "Plan with AI" job tracking is a thin separate module, `MealPlanJobs`
  (`meal_plan_jobs.ex`), feeding the `meal_plan:<user_id>` channel (mobile spec §9/§13).

## Why `Plans` is legacy but **not** dead

`Mehungry.Plans` predates `MealBlueprints`/`History` and is **not** removed — it still backs:

- **Nutritionist meal-plan ratings** — `Professionals.MealPlanRating` FKs
  `Plans.DailyMealPlan` / `Plans.MealPlan`.
- **Recipe-deletion cleanup** — `Food.{recipes,ingredients}` `delete_all` `Plans.Meal` rows
  that reference a recipe being deleted, so the legacy tables don't dangle.
- A nutritionist LiveView (`client_detail.ex`) still reads it.

So treat `Plans` as **read/maintain-only legacy**: don't build new features on it (use
`MealBlueprints` for templates, `History` for the calendar), but don't assume it's safe to
drop until the rating + cascade references are migrated.

## Rule of thumb

- Logging/eating against a plan → **`History`**.
- Authoring a reusable target → **`MealBlueprints`**.
- Publishing/sharing a week publicly → **`PublishedPlans`**.
- Generating a plan with AI → **`AI.MealPlanGenerator`** (writes into the first two).
- Touching `MealPlan`/`DailyMealPlan`/`Meal` → you're in **legacy `Plans`**; check why.
