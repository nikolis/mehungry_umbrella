# Snack ingredients (curated dried nuts + fresh fruit)

**Status:** shipped (2026-11-24): curation of dried nuts and fresh fruit (season-gated),
**read by both meal-plan agents** through `list_snack_options` (Phase 3 of the
composition rules, `docs/implementation/ai/meal_plan.md`).

## Why
The meal planner needs a short, vetted list of foods it can drop into a snack slot (or
next to a breakfast) without generating a recipe. The planned snack rules:

- **Morning snack:** seasonal fruit, optionally with nuts.
- **Afternoon snack:** nuts, optionally with seasonal fruit.

The lists are chosen by a person, not by a category filter. USDA's "Nut and Seed
Products" also holds nut butters, salted/oil-roasted variants and seed flours, and
"Fruits and Fruit Juices" holds juices and canned fruit. A human should decide which
of those belong.

## Data model
`snack_ingredients` (`Mehungry.Food.SnackIngredient`)

| column | notes |
|---|---|
| `ingredient_id` | FK `ingredients`, `on_delete: :delete_all` |
| `kind` | `"dried_nut"` or `"fresh_fruit"` (`SnackIngredient.kinds/0`) |
| `added_by_id` | FK `users`, `on_delete: :nilify_all`, the admin who added it |
| timestamps | |

Unique index on `(ingredient_id, kind)`.

## Seasonal fruit
`Food.seasonal_fruit_ids(country, month)` is the set the planner reads:

```
curated "fresh_fruit" ingredients
  ∩ ingredients curated onto a species (FoundementalFood) that is on the market
    (grown locally or imported) in that country that month (Food.SeasonalAvailability)
```

- "On the market" means the seasonality `local` value is `in_season`,
  `greenhouse`, `stored` or `unresolved` (on the market all year, e.g. apples), **or**
  the `imported` value is `some` / `major` (imports need a `comext` mapping on the
  species — see [`../seasonality.md`](../seasonality.md)).
- A curated fruit whose ingredient isn't curated onto a species, or whose species has
  no seasonality data, is **never offered**: its season is unknown.
- The country is the person's `user_profiles.country`. For a nutritionist's draft it is
  the client's country.
- If no fruit qualifies, the morning snack falls back to nuts (the tool's `note`
  says so). If **no nut** is curated (or every nut is excluded by the person's
  diet/avoid list), the run falls back to the open ingredient search and the
  fruit/nut snack rule is off — so curate nuts first.
- **An empty fruit list means nuts for every snack.** `seasonal_fruit_ids/2` returns
  nothing when no `fresh_fruit` is curated at all — not only out of season — so a
  fresh install must curate fruit too. Prod was first curated 2026-11-24 (apples,
  bananas, clementines, table grapes, kiwifruit, oranges, pears, tangerines); the nut
  list was pruned to one plain, unsalted entry per nut (no honey-roasted / glazed /
  salted / duplicate rows).
- Snacks must also **vary**: the `:snack_variety` rule caps one snack food at 2
  snack slots per plan (more only when its pool is too small) — see
  [`../ai/meal_plan.md`](../ai/meal_plan.md).

`Food.SeasonalAvailability` is core's read seam into the separate seasonality app. See
[`../seasonality.md`](../seasonality.md) → *Core seam*.

## Context: `Mehungry.Food.SnackIngredients`
Every function is also delegated through the `Mehungry.Food` facade:

| sub-module | facade |
|---|---|
| `list_selected/1` | `list_snack_ingredients/1`: rows with ingredient + category preloaded, by name |
| `selected_ids/1` | `snack_ingredient_ids/1`: MapSet of ingredient ids (the nut reader) |
| `seasonal_fruit_ids/2` | `seasonal_fruit_ids/2`: curated fruit in season for (country, month) |
| `add/3` | `add_snack_ingredient/3`: idempotent (`on_conflict: :nothing`) |
| `remove/2` | `remove_snack_ingredient/2` |
| `search_candidates/2` | `search_snack_candidates/2`: global (`user_id IS NULL`) ingredients only (details below) |

`search_candidates/2` behaviour:
- Every search word must appear in `search_name`; shortest name first; 50 per page.
- `kind:` picks a category keyword (`"nut"` / `"fruit"`), and `category_only: true`
  (the default; `nuts_only` is the old name) restricts results to categories whose name
  contains it, so no category id is hardcoded.
- A blank term with `category_only` lists the whole category.

## Admin page
`/professional/snack-nuts` → `MehungryWeb.ProfessionalLive.SnackNuts` (`:default2`,
admin-gated, sidebar "Snack foods"):
- Tabs **Dried nuts** / **Fresh fruit** (`?kind=dried_nut|fresh_fruit`). The fruit tab
  explains the season gate and links to Seasonality.
- **Selected** panel: the current list, each with a Remove button.
- **Find ingredients** panel: a debounced search and a "<kind> categories only" toggle
  (on by default). Each result has Add, or "Added ✓", which removes on click. Results
  page with "Load more".
