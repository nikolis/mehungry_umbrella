# Meal Blueprints

**Status:** shipped and reshaped into a two-audience product.

- **Authoring is nutritionist-only.** The blueprint library + editor + generation
  live under the gated `:nutritionist` section at **`/nutritionist/blueprints`**
  (only the `"pro"` tier reaches it, via `NutritionistAuthLive`). A nutritionist
  authors a blueprint, marks it **public or private** (`visibility`), generates
  sample `BlueprintPlan`s against its targets, and can **edit those generated
  meals** (swap a slot's recipe, adjust portions/quantity, remove a slot).
- **Public blueprints are shareable.** A public blueprint has a `slug` and a
  synchronously-rendered preview page at **`/blueprints/:slug`** with Open Graph
  meta (so a link dropped in a Facebook group renders a rich card) plus a
  Facebook share-dialog link and a copy-link button. The preview shows the
  targets and the attached sample plans.
- **Regular users browse, save, and personalize.** `/browse` has a
  recipes↔blueprints toggle (title keyword search over public blueprints). A
  logged-in user **saves** a blueprint (shows under `/profile?tab=saved_blueprints`)
  and taps **Use this blueprint** → `/calendar?blueprint_id=…`, which preselects
  it in the AI-plan panel and generates a personal week onto their calendar
  (governed by their existing `"meal_plan"` quota — free = 0, premium tiers can).

Generation stores the result as an **independent** `BlueprintPlan` (not calendar
entries); plans list under their blueprint in an accordion and each can be
**imported** to the calendar on a chosen start date (see *Generated plans* below).

## Generated plans (phase 2)

The blueprint library's **Generate** button (next to Edit/Duplicate/Delete) kicks
off an async `Task` calling `AI.MealPlanGenerator.generate_entries/5` with a
free-text brief distilled from the blueprint
(`MealBlueprints.blueprint_preferences/1` — name, description, condition,
required/avoid nutrient & compound names, preferred foods). Quota is
checked/recorded via `Subscriptions` under the `"meal_plan"` key.

**Generated plans are independent instances, not calendar entries.** Generation
returns *normalized, calendar-independent entries* (`MealPlanAgent.normalize_entry/2`
— relative `day_index` 1..7, canonical `meal_type`, and a recipe **or** ingredient
with unit resolved to FKs). The LiveView stores them via
`MealBlueprints.store_plan_meals/2` as **`BlueprintPlanMeal`** rows
(`meal_blueprint_plan_meals`). A meal can hold a recipe (`recipe_id` +
`cooking_portions`) **and/or** any number of whole-food ingredients — the
ingredients live in a child table **`BlueprintPlanMealIngredient`**
(`meal_blueprint_plan_meal_ingredients`: `ingredient_id`, `quantity`, resolved
unit FKs) via `has_many :ingredients` (`on_replace: :delete`), mirroring the
calendar's `History.UserMeal` → `IngredientUserMeal`. Generation seeds one
ingredient child per ingredient slot; the nutritionist can then add more by hand.
These rows hang off a **`BlueprintPlan`**
(`meal_blueprint_plans`: `name`, `start_date`, `status`
`generating→completed|failed`, `meals_count`, `error`, `imported_at`,
`blueprint_id` cascade FK, `user_id`). Nothing touches the calendar at this
point. Multiple plans per blueprint coexist so the user can pick one.

`list_plans_for_blueprint/2` → `list_plan_meals/1` loads a plan's rows
(recipe/ingredient/measurement_unit/ingredient_portion preloaded), day+slot
ordered. The accordion groups by `day_index` ("Day N"), labels each row's slot
(`MealType.label/1`), and renders recipes as a compact thumbnail row ("N servings
· Easy/Medium/Difficult · N min") and ingredients as a name + `quantity
unit_label` row. Deleting a blueprint cascades its plans (and their meals).

**Import to calendar.** The plan header's **Import** button opens a date-picker
modal; `import_plan_to_calendar/3` lays `day_index` 1..7 onto
`chosen_date`..`+6`, creating `History.UserMeal` rows (via
`MealPlanGenerator`-style attrs) stamped with the nullable
`history_user_meals.blueprint_plan_id` FK (`on_delete: :nilify_all`). Recipe
meals get **`consume_portions: 1`** (not `0`) so the calendar's nutrient summary
— which scales by `consume_portions / servings`
(`NutrientUtils.summarize_meals_nutrients/1`) — shows real numbers; ingredient
meals get live-computed nutrition (`History.scaled_ingredient_nutrients/2`).
**Re-import is allowed** (a `data-confirm` warns when re-importing an already
imported plan); `imported_at` flags the plan and shows an "imported" badge.

**Generation covers all 5 blueprint slots and both meal kinds.** `MealPlanAgent`
plans Breakfast, Morning Snack, Lunch, Afternoon Snack, Dinner (35 entries). A
slot may be a **recipe** (via `search_catalog`) or a single whole-food
**ingredient** (via the `search_ingredients` tool → `Food.IngredientSearch`, which
already excludes prepared "second-layer" categories) — snacks are typically an
ingredient (fruit, nuts, cheese, yogurt). `submit_plan` entries carry **either**
`recipe_id` (+ `cooking_portions`) **or** `ingredient_id` (+ `quantity` +
`unit_selection`); `validate_plan/7` provenance-gates both id kinds, and
normalization sanitises a bad `unit_selection` back to grams. The agent no longer
persists — it returns entries; `MealPlanGenerator.run/5` (calendar path) persists
them, while the blueprint path stores them as an independent plan.

Migrations: `20260919130000_create_meal_blueprint_plans.exs`,
`20260919140000_create_meal_blueprint_plan_meals.exs` (+ `imported_at`).

A **meal blueprint** is a reusable, user-owned *targets document* organised in
three levels of increasing specificity:

- **Blueprint** — an optional disease/`Health.Condition` scoping the whole week
  (e.g. *"Ulcerative Colitis Weekly blueprint"*) **plus the "general" targets that
  apply across every day**: **required** and **avoid** lists for both nutrients
  and bioactive compounds (all chosen from the actual database via a searchable
  chip picker, persisted as name arrays), and free-text preferred foods.
- **Day** (7 of them) — just an optional total calorie aim + the 5 meal rows.
- **Meal** (the 5 calendar slots per day) — the "specific" targets: a macro
  **percentage split** (protein / carbs / fats, always totalling 100 %; default
  30 / 40 / 30) + a note.

It holds **no recipes** — it is the *aim*, not the plan. Users author it by hand
in a dedicated editor; a later phase lets the existing AI planner generate an
actual calendar week that honours a selected blueprint's targets.

## Context & domain (`Mehungry.MealBlueprints`)

Standalone context (no facade delegate — only `Food`/`Accounts`/`Users` are
permanent facades). Files under `apps/mehungry/lib/mehungry/meal_blueprints/`.

### Schema — three-level nested tree

Mirrors the legacy `Plans.{MealPlan,DailyMealPlan,Meal}` `cast_assoc` shape but
with the modern `belongs_to :user`.

| Schema (table) | Key fields |
|---|---|
| `Blueprint` (`meal_blueprints`) | `name`, `description`, `belongs_to :user`, `belongs_to :condition` (optional disease, `Health.Condition`), `required_nutrients` / `avoid_nutrients` / `required_compounds` / `avoid_compounds` / `preferred_foods` (all `{:array,:string}`), `has_many :days` |
| `BlueprintDay` (`meal_blueprint_days`) | `day_index` (1..7), `total_calorie_target` (int, optional), `has_many :meals` |
| `BlueprintMeal` (`meal_blueprint_meals`) | `meal_type` (one of `History.MealType.values/0`), `protein_pct`, `carbs_pct`, `fats_pct` (integers, must total 100; default 30/40/30 via `BlueprintMeal.default_split/0`), `note` |

Migrations: `apps/mehungry/priv/repo/migrations/20260905000001_create_meal_blueprints.exs`
— cascade FKs (`on_delete: :delete_all`), `condition_id` FK `on_delete:
:nilify_all`, unique `[:blueprint_id, :day_index]` and
`[:blueprint_day_id, :meal_type]`; then
`20260919120000_meal_blueprint_meal_macro_percentages.exs` swaps the per-meal
gram columns (`protein_min_g`/`protein_max_g`/`sugar_max_g`/`carbs_max_g`) for
the `protein_pct`/`carbs_pct`/`fats_pct` integer split (defaults 30/40/30).

**Nutrients/compounds are stored as name strings, not FK ids** — they are
DB-*sourced* (the picker's options come from `Food.list_nutrients/0` /
`Food.list_compounds/0` + the compound-type families), but persisted as
`{:array,:string}`. This keeps `Presets` (which emit names) trivial and matches
the existing tag-column shape. Only the **disease** is a real entity link
(`condition_id`).

**Validations:** exactly 7 distinct `day_index`; `meal_type` via
`MealType.valid?/1` (kept coupled to the single source of truth — no hardcoded
list); each macro percentage in `0..100` and the three **must total exactly
100**; blueprint-level tag arrays trimmed, deduped and blank-stripped
(`Blueprint.clean_tags/2`).

**Meal slots** are the same five the calendar supports
(`Mehungry.History.MealType`): `breakfast, morning_snack, lunch,
afternoon_snack, dinner`. Blueprint-level condition + required/avoid
nutrients/compounds, day-level calorie aim, and per-meal macro split match the
product intent ("Ulcerative Colitis week requiring Vitamin C + Polyphenols and
avoiding Oxalate; Day 1 total 2000 kcal; Breakfast 30 % protein / 40 % carbs /
30 % fats…").

### Context API (`apps/mehungry/lib/mehungry/meal_blueprints.ex`)

- `list_blueprints_for_user/1` — newest first, light preload.
- `get_blueprint!/2` — **owner-scoped**; loads the full tree, meals ordered by
  canonical slot order.
- `create_blueprint/1`, `update_blueprint/2`, `delete_blueprint/1` (cascade),
  `change_blueprint/2`.
- `duplicate_blueprint/2` — deep-copy (incl. `condition_id` + the blueprint-level
  tag arrays), default name `"Copy of <name>"`.
- `default_blueprint_attrs/2` — canonical empty 7×5 skeleton builder (the single
  source of the grid shape).
- `to_targets_map/1` — serialize the tree to primitives for the phase-2 AI layer
  (so the agent never touches Ecto structs); includes the top-level `condition`
  name and the blueprint-level nutrient/compound/preferred-food arrays.
- `recommended_compounds_for_condition/1` — a condition's recommended
  bioactive-compound **names** bucketed by direction (`%{required: [...], avoid:
  [...]}`, via `Health.recommendations_for_condition/1`: `encourage` → required;
  `avoid`/`limit`/`caution` → avoid; `monitor` ignored), used by the editor to
  auto-suggest blueprint-level compounds when a disease is selected.

## Presets — production starter blueprints

`Mehungry.MealBlueprints.Presets`
(`apps/mehungry/lib/mehungry/meal_blueprints/presets.ex`)

**36 ready-made blueprints** spanning **sex × activity × age band**:
`female|male` × `no exercise|some exercise|regular exercise` × `20s..70s`.
Descriptive names, e.g. `"Female · 30s · Regular exercise (2200 kcal/day)"`.

- Daily calorie aims follow the USDA/HHS *Estimated Calorie Needs* table
  (`no exercise→sedentary`, `some→moderately active`, `regular→active`), one
  representative value per decade.
- Per-meal macro split follows energy ratios by activity: protein 20/25/30 %E,
  carbs 50/48/45 %E, fat the remainder 30/27/25 %E (each triple totals 100). The
  same split applies to every slot; the day carries the absolute calorie aim.
- Preferred foods and required nutrients are aggregated onto the **blueprint**
  (union across the five slots), plus **cumulative life-stage** nutrient
  additions: reproductive-age women (20s–40s) → Iron/Folate; women 50s+ →
  Calcium/Vitamin D; anyone 60s+ → Vitamin B12/Vitamin D. Presets leave the
  compound + avoid lists empty
  (`required_compounds`/`avoid_nutrients`/`avoid_compounds` = `[]`) and no
  `condition_id` (generic starters).

**Usage:**

```elixir
Mehungry.MealBlueprints.Presets.all()                    # 36 descriptors (for a picker)
preset = Mehungry.MealBlueprints.Presets.get(:female, :regular, 30)
attrs  = Mehungry.MealBlueprints.Presets.attrs_for(preset, user_id)   # create_blueprint/1 attrs
{:ok, bp} = Mehungry.MealBlueprints.Presets.create_for_user(user_id, :male, :some, 40)
```

Presets carry no `user_id`; they are **instantiated per user** (a starter the
user then tweaks). A test inserts all 36 to guarantee they are valid/insertable
in production.

## Web layer

Authoring routes live in the gated `:nutritionist` `live_session`
(`NutritionistAuthLive`, `"pro"` tier only):

```
/nutritionist/blueprints            MealBlueprintLive.Index   :index
/nutritionist/blueprints/new        MealBlueprintLive.Index   :new
/nutritionist/blueprints/:id/edit   MealBlueprintLive.Editor  :edit
```

The public preview route is in the `:maybe` (anonymous-OK) session, via `localized_live`:

```
/blueprints/:slug                   BlueprintLive.Show        :show
```

- **`MealBlueprintLive.Index`** — library of blueprint cards (Generate / Edit /
  Duplicate / Delete) with a visibility badge and a "View public" link when
  public; `:new` opens a name-only `core_components` modal that seeds the 7×5
  skeleton and jumps to the editor. Each generated plan's meals can be **edited
  in place** (`MealBlueprintLive.PlanMealFormComponent`): the *Edit* modal has an
  optional recipe picker (+ cooking portions) **and** an ingredients section — a
  repeatable list of ingredient rows (each with a quantity + unit `<select>`)
  plus one "Add ingredient" `SelectComponentDeep` search that appends a row. A
  meal can therefore mix a recipe with several ingredients. Rows are held in
  socket state (per-row live pickers would collide on a shared form field) and
  written on save via `update_plan_meal/2` (`cast_assoc` replaces the ingredient
  children); *✕* removes the whole slot (`delete_plan_meal/1`).
- **`BlueprintLive.Show`** (public) — synchronous render of a public blueprint
  (targets + attached sample plans) with OG/SEO assigns (`page_title`,
  `page_description`, `canonical_path`), a Facebook share-dialog link, copy-link,
  and (for logged-in visitors) a Save toggle + "Use this blueprint" → calendar.
- **`RecipeBrowserLive`** — a recipes↔blueprints segmented toggle
  (`set_browse_mode`); blueprint mode lists `list_public_blueprints/1` and
  searches titles via `search_public_blueprints/2`, rendered with the shared
  `MehungryWeb.BlueprintComponents.blueprint_card/1`.
- **`ProfileLive.Index`** — a `saved_blueprints` tab lists
  `list_saved_blueprints_for_user/1` (unsave via `unsave-blueprint`).
- **`MealBlueprintLive.Editor`** — full-page editor:
  - A blueprint-level panel with the **condition** native `<select>` (from
    `Health.list_conditions/0`), **four searchable chip multi-selects**
    (required/avoid × nutrients/compounds; avoid chips are paprika-tinted) and a
    free-text preferred-foods field — all bound to the top-level `@form`. Changing
    the condition auto-suggests its recommended compounds
    (`recommended_compounds_for_condition/1`) into the compound pickers —
    encouraged → *required*, discouraged → *avoid* (merged, editable). Health
    links conditions to *compounds* only, so nutrients stay manual.
  - 7 collapsible day panels, each with just a calorie-aim field and 5 meal cards
    (protein/carbs/fats % number inputs — with a live "Total: X%" hint that turns
    paprika when the split ≠ 100 — + note) via nested `inputs_for`.

  The chip pickers are **not** the shared `SelectComponent` (its multi mode
  doesn't repopulate chips from a persisted `{:array,:string}` on edit-load).
  They are a small self-contained widget (`tag_multiselect/1`) managed by
  `search_tag`/`add_tag`/`remove_tag` server events on the working changeset —
  the same apply-changes-then-rebuild pattern the copy shortcuts use — rendering
  hidden `name[...][]` inputs (plus an empty sentinel so a fully-cleared field
  still posts) so selections survive submit. The rendered chip list is
  blank-filtered (`tag_list/1`): after a validate, Phoenix reflects the raw
  submitted param — including that `""` sentinel — back into `form[field].value`
  (the cleaned changeset value equals the data, so Ecto drops the change and the
  form falls back to the param), which would otherwise show as an empty chip. The
  add/remove events pass the tag as **`phx-value-tag`** (never `phx-value-value`:
  in the browser a `<button>`/`<li>`'s native empty `value` property overrides
  `phx-value-value`, so the handler receives `""` — a bug that `render_click`
  can't reproduce, since LiveViewTest sends the attribute literally). **`phx-click-away`
  lives on the dropdown `<ul>`, not the widget root:** only the single active
  picker renders a `<ul>`, so exactly one click-away handler is live at a time
  (one per widget let the other pickers' handlers slam the dropdown shut the
  moment you touched any one of them). Preferred-food comma tags are split into an
  array in `normalize_params/1`. **Copy shortcuts** ("Copy this day to all days",
  "Copy this meal to every day") are server events operating on the current
  changeset.

**Navigation:** a "Blueprints" link (icon `hero-clipboard-document-list`) sits in
the **nutritionist sidebar** (`LayoutView.nutritionist_sidebar/1`) with a matching
stat tile on `NutritionistLive.Dashboard`. It is **no longer** in the main/mobile
menus (authoring is nutritionist-only).

## AI planner seam

The calendar's "Plan with AI" panel has a **"Follow blueprint"** dropdown plus a
"Browse" link. It is populated by owned blueprints ∪ the user's **saved** public
blueprints; arriving via `/calendar?blueprint_id=…` (the preview's "Use this
blueprint") preselects the blueprint and opens the panel. The selection threads a
`blueprint_id` through `handle_event("ai_plan_week", …)` →
`Mehungry.AI.MealPlanGenerator.run/5` → `Mehungry.AI.Agents.MealPlanAgent.run/5`.
The blueprint is resolved with `get_blueprint_for_generation/2` (owned **or**
saved **or** public) and its targets reach the planner as the free-text brief
from `blueprint_preferences/1`. The agent already plans all **5** slots × 7 days
and supports recipe-or-ingredient slots.

> Still open (not blocking this feature): threading the *structured*
> `to_targets_map/1` (per-day calorie + macro split) and resolving compound names
> against `Food.Compounds` into the agent, rather than only the free-text brief.

## Quota

Generation is gated by the existing `"meal_plan"` quota key
(`Mehungry.Subscriptions.check_quota/2`). A nutritionist authoring/generating
uses their `"pro"` allotment; a regular user personalizing a blueprint on their
calendar uses their own tier's allotment (free = 0 → blocked). Blueprint
**authoring** itself is not quota-gated.

## Tests

- `apps/mehungry/test/mehungry/meal_blueprints_test.exs` — context: skeleton
  shape, default 30/40/30 macro split, create/validate rejects (bad day_index /
  meal_type / macro split ≠ 100 / negative percentage), owner-scoping, duplicate
  deep-copy, delete cascade, list scoping/order, blueprint-level tag
  trimming/dedup, optional condition round-trip, direction-bucketed
  `recommended_compounds_for_condition/1`. Plus (this feature): visibility default
  + slug generation/uniqueness/validation, `get_public_blueprint_by_slug!/1`
  (public returns / private raises), `search_public_blueprints/2`, saved-blueprint
  round-trip + scoping + idempotency, `get_blueprint_for_generation/2`
  (owned/saved/public allowed, foreign-private raises), and `get_plan_meal!/2` /
  `update_plan_meal/2` / `delete_plan_meal/1`.
- `apps/mehungry/test/mehungry/meal_blueprints/presets_test.exs` — all 36 build
  & insert valid; descriptive names; 7×5 shape; blueprint-level nutrients/
  preferred foods with cumulative life-stage requirements; days/meals carry no
  general targets.
- `apps/mehungry_web/test/mehungry_web/live/meal_blueprint_live_test.exs` —
  (now nutritionist-gated setup) index list, new→editor redirect, edit+save
  persistence (macro split + blueprint-level nutrient/compound/preferred arrays),
  condition compound auto-suggest, search/add/remove chips, the
  blank-sentinel-not-an-empty-chip guard, copy shortcuts, delete.
- `apps/mehungry_web/test/mehungry_web/live/blueprint_live_test.exs` — public
  preview renders content + OG meta for anonymous visitors, private 404s, save
  toggle for logged-in users, browse toggle shows/searches blueprint cards, and
  a non-nutritionist is redirected from `/nutritionist/blueprints`.

**Verified end-to-end** in the running app (browser): create via modal →
editor with 7 days × 5 meals → pick DB nutrients/compounds as chips → select a
disease and watch its recommended compounds populate the days → edit macros →
save → DB persistence exact → reopen round-trips (chips + condition + macros) →
calendar dropdown lists the blueprint → "Copy to every day" propagates to the
correct slot only.

## Related

- Calendar / `History` model (where a generated plan would land):
  `apps/mehungry_web/lib/mehungry_web/live/calendar_live/index.ex`,
  `Mehungry.History.{UserMeal, RecipeUserMeal, IngredientUserMeal}`.
- Meal-type vocabulary: `Mehungry.History.MealType` (kept in sync with
  `AiBotConfig.meal_types/0` by a drift-guard test).
- Nutrient data a generator would score against: `recipe.nutrients` +
  `Mehungry.Food.Nutrition.NutrientHierarchyBuilder`.
