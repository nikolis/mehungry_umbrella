# Add Sodium + Saturated Fat badges to the calendar day/week summary

## Context

The self-tracker's day/week summary badge row (`summary_tags` in the calendar
widget) stops at **meals · items · kcal · protein · fat · carbs · sugars · fiber**.
For the conditions people actually track (hypertension, heart health, kidney
diet), **sodium** and **saturated fat** are the two numbers that matter most, and
they already surface elsewhere (blueprint avoid-chips for DASH/MIND/Low-Sodium,
the full Nutrition Facts accordion) — but not on the at-a-glance summary row.

`sugars` and `fiber` badges already exist, so the genuinely new additions are
**Sodium (mg)** and **Saturated Fat (g)**.

The wrinkle: the aggregated nutrient map from
`NutrientUtils.summarize_meals_nutrients/1` is a **hierarchical tree**
(`NutrientHierarchyBuilder`): top-level keys are `Energy`, `Total Fat`,
`Carbohydrates`, `Protein`, `Fiber`, `Total Sugars`, `Vitamins`, `Minerals`.
`Saturated Fat` is a **child of `Total Fat`** and `Sodium` is a **child of the
`Minerals` umbrella** — so, unlike the macro buckets, neither is reachable as a
top-level key. Extraction needs a small tree-walk by canonical name.

## Approach

Single source of truth stays `NutrientUtils.macro_summary/1` (consumed by the
calendar header, the weekly-plan share card, and `published_plans`). Extend it
with two new keys; downstream consumers that only read the existing 6 keys are
unaffected (extra map keys are ignored; the weekly-plan test uses partial map
match).

### 1. `apps/mehungry/lib/mehungry/nutrient_utils.ex`

- Add a private tree-walker that finds the first node whose name normalizes to a
  target canonical name, searching the top-level map **and recursing into
  `"children"`** (so `Saturated Fat` under `Total Fat` and `Sodium` under
  `Minerals` are both found). Match via the module's own
  `normalize_nutrient_name/1`. Return the node (or its `{amount, unit}`), nil if
  absent. Mirror the existing `energy_scalar/1` style and reuse
  `RecipeUtils.to_grams/2` for unit conversion. (Reference the existing private
  `sum_label_in_tree/2` tree-walk in `meal_blueprints/plan_compatibility.ex:694`
  for the descend-children shape, but keep this helper local and simpler.)
- In `macro_summary/1` (around line 498-513) add:
  - `sodium_mg:` — walk for `"Sodium"`, convert amount via `to_grams/2` then
    `* 1000`, round to integer mg; `0` when absent/unconvertible.
  - `saturated_fat_g:` — walk for `"Saturated Fat"`, convert via `to_grams/2`,
    `Float.round(_, 1)`; `0.0` when absent.
- Update the `macro_summary/1` `@doc` to mention the two added keys.

### 2. `apps/mehungry_web/lib/mehungry_web/live/calendar_live/calendar/widget.ex`

- `summary_tags/1` (lines 158-190): after the fiber badge, add two badges —
  Sodium (`{@sodium_mg}mg`) and Sat. fat (`{@saturated_fat_g}g`) — each wrapped
  in `:if={@sodium_mg > 0}` / `:if={@saturated_fat_g > 0}` per the confirmed
  **hide-when-zero/missing** decision. Same `bg-ink-panel2 … text-basil` chip
  styling as the others; labels via `gettext("sodium")` / `gettext("sat. fat")`.
- `summary_card/1` (the explicit `<.summary_tags .../>` call at lines 285-295):
  add `sodium_mg={@sodium_mg}` and `saturated_fat_g={@saturated_fat_g}`.
  These flow in automatically via `summary_assigns → summary_metrics →
  Nu.macro_summary` (line 125), so no new plumbing is needed — the keys land on
  the assigns map already merged in `summary_metrics/3`.
- `day_header_tags/1` (line 211) already splats `{@metrics}`, so it picks up the
  new keys with no change.
- Because both the daily and weekly cards render through the same `summary_tags`,
  the two badges appear on the weekly summary too (desired — weekly is a
  daily-average via `scale_nutrients`, and `macro_summary` runs on the scaled
  map so the mg/g values are already per-day averages).

### 3. Localization

Follow the existing inline-`gettext` pattern in `summary_tags` (the other badge
labels already use `gettext("protein")` etc.). New strings `"sodium"` and
`"sat. fat"` — extractable later with `mix gettext.extract` if EL copy is wanted;
no `NutrientLabels` change required (these are badge labels, not DB nutrient
display names).

## Reuse notes

- `NutrientUtils.macro_summary/1` — extend, don't fork (single source for header
  + share card + published plans).
- `Mehungry.Food.RecipeUtils.to_grams/2` — unit → grams conversion (handles
  g/mg/µg), already imported-adjacent in the widget.
- `NutrientUtils.normalize_nutrient_name/1` — canonical-name matching for the
  tree-walk.

## Verification

1. **Unit test** (`apps/mehungry/test/mehungry/weekly_plan_share_test.exs` or
   `nutrient_utils_test.exs`): build a nested `total` map with
   `"Total Fat" => %{… "children" => [%{"name" => "Saturated Fat", "amount" =>
   12.0, "measurement_unit" => "g"} …]}` and
   `"Minerals" => %{"children" => [%{"name" => "Sodium", "amount" => 1500.0,
   "measurement_unit" => "mg"} …]}`; assert `macro_summary/1` returns
   `sodium_mg: 1500` and `saturated_fat_g: 12.0`. Add an "absent → 0" case.
   Run: `mix test apps/mehungry/test/mehungry/weekly_plan_share_test.exs`.
2. **Full suite / regression** on the touched contexts:
   `mix test apps/mehungry/test/mehungry/nutrient_utils_test.exs` and the
   weekly-plan test (confirms the extra keys didn't break partial-match asserts).
3. **End-to-end in the app**: `iex -S mix phx.server`, open `/calendar`, expand a
   day that has a recipe with sodium/sat-fat data (e.g. anything with cheese/meat)
   and confirm the two new badges appear on the Daily Summary header and the
   Weekly Summary; confirm a day whose meals lack the data shows **no** zero
   badges. Drive it with the chrome-devtools MCP (navigate `/calendar`, snapshot
   the day header) rather than only trusting tests.
