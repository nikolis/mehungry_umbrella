# Audit — `apps/mehungry_web/lib/mehungry_web/live/calendar_live/**`

_Reviewed: 2026-08-08 · Scope: every file under `calendar_live/` (LiveView, live_components,
function components, `.heex` templates). Severity: 🔴 high · 🟠 medium · 🟡 low.
Cited as `file:line`. **(verify)** = pattern/inference, confirm before acting._

Files in scope:
```
index.ex / index.html.heex
meal_form_component.ex / meal_form_component.html.heex
components.ex  (+ components/{recipe,ingredient,consume_recipe}_user_meal.html.heex)
calendar/widget.ex          (917 lines — the big one)
calendar/pie_chart.ex
calendar/locale.ex
.components.ex.swp           ← stray editor swap file
```

---

## 1. Security / Authorization

### 🔴 IDOR — meals are fetched, edited, and deleted with no owner check
`index.ex:84` (`apply_action(:edit)`), `index.ex:277` (`delete_user_meal`),
`meal_form_component.ex:46` (`get_user_meal_raw!(id)`), backed by
`Mehungry.History.get_user_meal!/1`, `get_user_meal_raw!/1`, `update_user_meal/2`,
`delete_user_meal/1` — **none scope by `user_id`** (`history.ex:163,177,220,238` are plain
`Repo.get!`/`Repo.delete`).

Any authenticated user can open `/calendar/<id>` or fire `delete_user_meal`/`edit_modal` with
**another user's** meal id and read/modify/delete it. The hidden `user_id` field in the form
(`meal_form_component.html.heex:13`) does not protect anything — the record is loaded by id alone.

**Fix:** scope every meal lookup by the current user, e.g.
`History.get_user_meal!(user_id, id)` (`where: m.user_id == ^user_id`), and have
`delete/update` verify ownership. Do this in the context so all call sites are covered.

---

## 2. Correctness / Bugs

### 🟠 `MealFormComponent.is_empty/2` can never return `true`
`meal_form_component.ex:16-26` — both the `if` and `else` branches `return false`. The helper is
dead logic (and `has_content/2` at `:28-30` is a hardcoded constant). Note the **correct**
versions already exist in `components.ex:65-87`. Delete the broken copies in
`meal_form_component.ex` and use the `Components` ones (or drop entirely if unused).

### 🟠 DOM id collisions from integer concatenation
`widget.ex:713` & `:735` build a card id as
`Integer.to_string(recipe_id) <> Integer.to_string(meal.id)`. Recipe `1` + meal `12` and recipe
`11` + meal `2` both yield `"112"`. Colliding ids break LiveView DOM patching / JS hooks.
**Fix:** join with a separator, e.g. `"#{recipe_id}-#{meal.id}"`.

### 🟠 Unhandled/raising input on user-driven events
- `index.ex:316,321` `rate_meal_plan`: `Date.from_iso8601!/1` and `String.to_integer/1` on
  client-supplied `date`/`score` raise (crash the LiveView) on malformed input.
- `meal_form_component.ex:297` `save_user_meal(:new)`: `{:ok, dt} = NaiveDateTime.from_iso8601(...)`
  hard-matches — a bad `start_dt` is a `MatchError`, not a validation error.
- `index.ex:263-272` `toggle_basket`: `case view do "week_view" -> ...; "day_view" -> ... end`
  has no fallback → `CaseClauseError` on any other value.
  **Fix:** validate/parse defensively and return a changeset error or `:noreply` on bad input.

### 🟡 `prev-month` / `next-month` are misnamed and move by one day
`widget.ex:544-546` `prev-month` computes `Date.add(current_date, 0) |> Date.add(-1)` (just
`-1` day, via a no-op `days = 0`); `:562` `next-month` adds `+1` day. The header says these page
the week, but they shift by a single day and are named "month". Clarify intent, rename, and drop
the `days = 0`/`Date.add(0)` noise.

### 🟡 Weekly rating is always tied to the *real* current week
`index.html.heex:176` hardcodes `Date.beginning_of_week(Date.utc_today())`. If the user has paged
the widget to another week, the rating is still recorded for today's week — likely a mismatch with
what they're looking at. **(verify** intended behavior).

---

## 3. Dead / broken code (large surface here)

### 🟠 `table_day_calendar/1` is unused **and** would crash if used
`widget.ex:756-794`. `render/1` (`:378`) only ever calls `table_week_calendar`. `table_day_calendar`
calls `.card_meal` (`:780`) passing only `actual_meal/img_url/title/myself`, but the `card_meal`
template requires `@card_meal_text` (`:820`), `@cooking_portions` (`:826`), `@consume_portions`
(`:830`) → `KeyError` at render. The whole `day_view` feature is half-built: `toggle_basket`
(`index.ex:263`) flips `:calendar_view`, but `render/1` ignores it. **Remove day-view or finish it.**

### 🟠 Dead resize/child-chart chain — `child_ids` is never populated
`index.ex:40` sets `child_ids: []` and nothing ever adds to it, so `handle_event("resize_chart")`
(`index.ex:221-227`) loops over an empty list and `send_update(PieChart, resize: …)` never fires.
Correspondingly `PieChart.handle_event("resize", …)` (`pie_chart.ex:23`) is unreachable, and
`update/2` (`pie_chart.ex:13`) hardcodes `width: 300` while `build_spec` (`:46-50`) computes
`_radius`/`_inner` (unused) and hardcodes `width: 100, radius: 50`. Net: `size`/`width`/resize are
all no-ops. Either wire responsive sizing properly or delete the resize plumbing.

### 🟠 Commented-out "Log consumption" leaves a chain of dead code
`meal_form_component.html.heex:104-130` (block commented, still using the *old* `slate-*/primary-*`
palette). Because of it, the following are dead: `consume_recipe_user_meal_render`
(`components.ex:42`), the `consume_recipe_user_meal.html.heex` template, and the handlers
`new_consume_recipe`, `delete_consume_record`, `delete_recipe_consume_record`
(`meal_form_component.ex:163-271` — the last two are near-identical duplicates). Remove them or
re-enable the feature.

### 🟡 `Locale` module duplicated inside `widget.ex`
`calendar/locale.ex` defines `day_name/2`, `month_short/2`, `@days_el`, `@months_short_el` — and
`widget.ex:888-916` **re-defines the same maps and functions privately**. `widget` never calls
`Locale`; `Locale.month_name/2`, `format_day_header/2`, `format_nav_header/2` appear unused. Make
`widget` delegate to `Locale` and delete the duplicates (single source for i18n).
_(Note: `@current_language` **is** provided by `UserAuthLive` on_mount and does flow through to the
widget, so Greek rendering works — this is duplication, not a broken-i18n bug.)_

### 🟡 Duplicated helpers across components
`get_not_nil/2`, `is_empty/2`, `has_content/2` exist in **both** `components.ex` and
`meal_form_component.ex` (the latter's are the broken ones from §2). Consolidate into one module.

### 🟡 `get_full_week/3` ignores two of its args; magic numbers passed for them
`widget.ex:527` signature is `(current_date, _user_meals, _device_width)`; callers pass
`1500`/`100`/`300` (`:412,549,566`) as a "device_width" that's discarded. Drop the unused params.

### 🟡 Unused assigns / props
- `index.html.heex:252,254` pass `title="Alter Basket"` and `action={@live_action}` to the widget;
  `Widget.update/2` (`widget.ex:401-443`) reads neither.
- `recipe_user_meal.html.heex` receives `mode`, `recipe_ids`, `myself` (via
  `components.ex:11-19`) but doesn't use them.
- Rating widget Alpine state `x-data="{dailyScore:0, weeklyScore:0, showRating:false}"`
  (`index.html.heex:136`) — `dailyScore`/`weeklyScore` unused (only a weekly form exists).

### 🟡 Stray editor swap file
`calendar_live/.components.ex.swp` is present in the working tree (not git-tracked). Delete it and
add `*.swp` to `.gitignore`.

### 🟡 Magic strings
`"landing_id"` (`widget.ex:808`), meal title `"r"` (`widget.ex:581`), placeholder meal
`"El diablo"` (`widget.ex:861`, which is then shadowed by the `pick-date` `%{"date"=>...}` clause
so it's never used). Replace with named constants or remove.

---

## 4. Performance

### 🟠 A DB query **per ingredient row, per render** for measurement units
`meal_form_component.html.heex:86-88` calls `get_measurement_units(f, index)` inside `inputs_for`,
and `meal_form_component.ex:12-14` runs `Food.get_measurement_unit_by_name("gram")` every call
(args ignored). With N ingredient rows that's N identical queries on every `validate`/render.
**Fix:** fetch the unit list once in `update/2`, pass it down as an assign.

### 🟠 Nutrient aggregation runs during template render, repeatedly
`widget.ex` computes `Nu.summarize_meals_nutrients/1` + sorting + slice-building inside render-time
functions: `get_chart` (`:8`, called per day at `:742`), `get_week_chart` (`:34`, `:750`), and
`day_header_tags` (`:187`, re-summarizing the *same* day already summarized by `get_chart`). All of
this re-executes on every LiveView update of the component. **Fix:** precompute per-day and weekly
summaries once in `update/2` and pass them as assigns; dedupe the day header vs day chart work.

### 🟠 `Widget.update/2` hits the DB on every re-render
`widget.ex:415-423` calls `Mehungry.Accounts.get_user_profile_by_user_id/1` each update just to
read `daily_calorie_target`. **Fix:** resolve `calorie_target` once in the parent `mount` and pass
it in (the parent already loads the profile at `index.ex:25-28`).

### 🟡 `MealFormComponent.update/2` runs two list queries every parent re-render
`meal_form_component.ex:49-50` (`Food.list_user_recipes_for_selection/1` +
`History.list_incomplete_user_meals2/2`). Acceptable for a modal, but they re-run on any assign
change; consider `assign_new` / gating so they run once per open.

### 🟡 Full reload + deep reshape of all meals on every change
`index.ex:339-384` `load_and_format_user_meals/1` reloads and deeply `Enum.map`s all history meals
on mount and after every save/delete/AI-plan. Fine at current scale **provided** the History
context preloads `ingredient_nutrients`, `nutrient.measurement_unit`, `recipe`, etc. (it must, or
this raises) — **(verify** the preload tree to avoid a latent N+1 as history grows).

---

## 5. Best practices / consistency

- 🟡 **Mixed routing helpers:** `Routes.calendar_index_path(...)` (`index.ex:290`,
  `index.html.heex:225,242`) alongside verified `~p"/calendar"` (`index.html.heex:210,232`).
  Standardize on `~p`.
- 🟡 **`@impl true` inconsistency:** several `handle_event` clauses lack `@impl`
  (`ai_plan_week`, `toggle_basket`, `delete_user_meal` in `index.ex:234-295`; the `handle_event`s
  in `meal_form_component.ex`). Add for clarity and to catch typos.
- 🟡 **`get_class_for_toggle_button/2`** (`widget.ex:846`) appears unused (the week/day toggle it
  served is dead) — remove with the day-view cleanup.
- 🟡 **Portions typed as text:** `recipe_user_meal.html.heex:40,43` use `type="text"` for
  `cooking_portions`/`consume_portions` (numeric). Use `type="number"` for better UX/validation.
- 🟡 **Positive controls flagged:** the AI-plan `Task.async` in `index.ex:242-256` is done
  **correctly** — ref stored, `Process.demonitor(ref, [:flush])` + `:DOWN` handled
  (`index.ex:153-194`). Keep this pattern; it's the model the `Task.start` calls elsewhere in the
  app should follow.

---

## 6. Suggested order of attack

1. 🔴 Scope meal fetch/update/delete by `user_id` (IDOR). — §1
2. 🟠 Fix DOM id collision + defensive parsing on `rate_meal_plan`/`save_user_meal`/`toggle_basket`. — §2
3. 🟠 Delete dead code: `table_day_calendar`/day-view, `child_ids`/resize chain, commented
   consumption block + its handlers/templates, `Locale` duplication, stray `.swp`. — §3
4. 🟠 Perf: hoist `measurement_units`, precompute nutrient summaries in `update/2`, pass
   `calorie_target` from parent. — §4
5. 🟡 Consolidate duplicated helpers, standardize routing/`@impl`, fix numeric input types. — §5

---

### Method note
Every file in the directory was read in full. Findings are from reading, not runtime profiling —
performance items are structural. The IDOR (§1), the always-`false` `is_empty` (§2), the dead
`table_day_calendar`/`child_ids` chains (§3), and the per-row measurement-unit query (§4) were
verified against the referenced source. Items tagged **(verify)** depend on context/behavior I did
not exercise.
