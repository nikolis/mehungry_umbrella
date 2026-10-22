# Nutrient Claim Badges

Truthful, per-serving "High in X" / "Source of X" badges for recipes —
**High in Iron**, **Source of Vitamin C**, etc.

The core idea: "high in iron" is **not** a subjective nutritionist judgment, it
is a **legally defined numeric threshold**. This feature applies the official EU
nutrition-claims framework, so a badge means exactly what a food label would mean.

Code: `Mehungry.Food.NutrientClaims`
(`apps/mehungry/lib/mehungry/food/nutrient_claims.ex`).
Facade: `Mehungry.Food`.

---

## The standard

Two layers of EU regulation:

- **Reference values** — Reg (EU) 1169/2011, **Annex XIII Part A** defines the
  adult **Nutrient Reference Value (NRV)** for each of 13 vitamins + 14 minerals
  (e.g. Iron 14 mg, Calcium 800 mg, Vitamin C 80 mg).
- **Claim thresholds** — Reg (EC) 1924/2006 Annex:
  - **"Source of" X** — the portion supplies **≥ 15%** of the NRV.
  - **"High in" / "Rich in" X** — **≥ 30%** of the NRV (exactly double).

EU (not US FDA) because the audience is ~98% Greece.

### Basis: per serving, not per 100 g

The regulation allows either per-100 g or per-portion. We use **per serving**
(`recipe total ÷ servings`):

- Per-100 g dilutes a watery dish — a soup/stew is mostly water, so *everything*
  reads "low" per 100 g even when a bowl is genuinely nutritious.
- Per-portion is both what the eater actually consumes **and** EU-legal (the
  per-portion claim allowance).

---

## The NRV table

The 22 nutrients that realistically have USDA ingredient data, keyed by the
canonical label `Food.NutrientNameNormalizer` emits for the stored nutrient tree:

| Nutrient | NRV | | Nutrient | NRV |
|---|---|---|---|---|
| Vitamin A | 800 µg | | Potassium | 2000 mg |
| Vitamin D | 5 µg | | Calcium | 800 mg |
| Vitamin E | 12 mg | | Phosphorus | 700 mg |
| Vitamin K | 75 µg | | Magnesium | 375 mg |
| Vitamin C | 80 mg | | Iron | 14 mg |
| Vitamin B1 (Thiamin) | 1.1 mg | | Zinc | 10 mg |
| Vitamin B2 (Riboflavin) | 1.4 mg | | Copper | 1 mg |
| Vitamin B3 (Niacin) | 16 mg | | Manganese | 2 mg |
| Vitamin B5 (Pantothenic Acid) | 6 mg | | Selenium | 55 µg |
| Vitamin B6 | 1.4 mg | | | |
| Vitamin B7 (Biotin) | 50 µg | | | |
| Folate (Vitamin B9) | 200 µg | | | |
| Vitamin B12 | 2.5 µg | | | |

**Deliberately excluded:**

- **Chloride, Fluoride, Chromium, Molybdenum, Iodine** — rarely present in USDA
  ingredient data, so badges would misfire from undercounting.
- **Sodium** — a *reduce* nutrient, never a positive "high in" badge (it's handled
  as a day-summary warning elsewhere, not here).

The full table is `NutrientClaims.nrv/0`; `nrv_grams/1` gives one NRV in grams.

---

## How a badge is computed

For each NRV nutrient, `NutrientClaims.badges/3`:

1. Locates the nutrient anywhere in the recipe's stored `nutrients` tree with
   `NutrientUtils.find_nutrient/2` (minerals/vitamins nest under
   `"Minerals"`/`"Vitamins"` umbrella nodes — the walker handles that).
2. Normalizes both the recipe amount **and** the NRV to grams with
   `NutrientUtils.to_grams/2`, so mg/µg never corrupt the ratio.
3. Divides by `servings` → per-serving grams.
4. Compares the fraction of NRV: `≥ 0.30` → `:high`, `≥ 0.15` → `:source`,
   else no badge.

Returns `%{nutrient: label, level: :high | :source, percent_nrv: integer}`,
**sorted by `percent_nrv` descending** (strongest first).

### Robustness (no false claims)

- `servings` nil / non-numeric / `≤ 0` falls back to `1` (the raw total).
- A nutrient missing from the tree, carrying a non-numeric amount, or stored in a
  non-mass unit (e.g. Vitamin A/D in `IU`, where `to_grams/2` returns `:error`)
  is **skipped** — no badge rather than a wrong one.

---

## The data-coverage gate

A recipe's nutrient totals silently **undercount** when some of its ingredients
have no `IngredientNutrient` rows (USDA data is incomplete). On its own that only
ever *hides* a badge (a safe false negative) — but a recipe built mostly from
data-less ingredients could still scrape past a threshold on its one data-rich
ingredient and **over-claim** "High in Iron". That is unacceptable on a public,
indexable surface, so badges are gated on a coverage ratio.

### The coverage ratio

`NutrientCalculation.nutrient_data_coverage/1` returns the **mass-weighted**
fraction of a recipe's grams that comes from ingredients carrying nutrient data:

```
coverage = Σ gram_weight(ingredients WITH nutrient data) / Σ gram_weight(all ingredients)
```

The signal is already in hand at calculation time:
`map_ingredients_to_structured_form/1` produces, per ingredient, both its
`:gram_weight` **and** a scaled `:nutrients` list — and that list is empty
**exactly when** the ingredient has no `IngredientNutrient` rows
(`build_nutrient_list/2` maps over them). So an empty list is the "no data"
marker; no new query or schema is needed. Ingredients whose unit didn't resolve
to grams (`gram_weight == 0.0`) drop out of both numerator and denominator —
their mass is unknown either way. Zero total mass → `0.0`.

The `with_coverage` entry point threads it out of the calculation layer:

```elixir
{primary_size, nutrients, coverage} =
  NutrientCalculation.calculate_recipe_nutrition_value_with_coverage(attrs)
```

(`calculate_recipe_nutrition_value/1` remains as a thin wrapper that drops the
coverage value, for callers that only want the totals.)

### The gate (policy lives in `NutrientClaims`)

`NutrientClaims.badges/3` takes a `:coverage` opt. When it is supplied and below
**`NutrientClaims.coverage_floor/0`** (currently **0.75**), **all** badges are
suppressed (`[]`). The gate is **all-or-nothing, not per-nutrient**: below the
floor the totals undercount systematically, so *every* claim is suspect — and the
failure mode stays a safe false negative (a missed badge) rather than a public
over-claim.

When the `:coverage` opt is **omitted**, the result is not gated — so
derive-on-read callers (which hold a loaded recipe but no ingredient data to
measure) behave exactly as before. The authoritative, gated badges are the ones
the write path persists to `recipes.badges`; every planned read surface reads
that column, so it never needs to re-derive or re-gate.

---

## Where badges are stored (the write path)

Badges are **persisted** on the recipe, in the `recipes.badges` jsonb column
(`{:array, :map}`, default `[]`). They are a pure function of `nutrients` +
`servings`, so they are computed in the **same chokepoint** that computes
`nutrients`: `Recipes.put_nutrient_info/2`
(`apps/mehungry/lib/mehungry/food/recipes.ex`).

```
create_recipe / update_recipe
        └─ enqueues RecipePutNutrientsWorker (:default queue)
               └─ Food.put_nutrient_info/2
                      ├─ calculate_recipe_nutrition_value_with_coverage/1
                      │      → {primary_size, nutrients, coverage}
                      ├─ put_change(:nutrients, …)
                      └─ put_change(:badges, …)   ← computed here, gated by coverage
```

`put_nutrient_info/2` passes the recipe's `coverage` into
`NutrientClaims.badges_for_storage(…, coverage: coverage)`, so a recipe below the
coverage floor persists `badges = []` (see **The data-coverage gate** above).

Because the worker runs on **every create and update**, badges are reassigned
automatically on both — no separate trigger. Timing matches `nutrients`:
**eventually consistent**, a moment after save (not synchronous), because
`nutrients` itself is computed by the async worker.

If a recipe loses its nutrition (all ingredients removed), the empty-nutrients
branch writes `badges = []` so a stale "High in Iron" can't linger.

### Atom-key vs string-key gotcha

At write time the freshly built `nutrients` tree is **atom-keyed**
(`%{name: …, amount: …}`), but `find_nutrient/2` reads **string keys**
(`node["amount"]`). `put_nutrient_info/2` therefore round-trips the tree through
JSON (`Jason.encode!/1 |> Jason.decode!/1`) before computing badges — the exact
same transform Ecto applies when it stores/reloads the jsonb. This guarantees the
**persisted badges equal a derive-on-read of the same recipe** (verified).

### Stored shape

`NutrientClaims.badges_for_storage/3` is the write-path variant: it returns
**string keys + string level**, so the jsonb is clean and predictable on reload
(mirroring how `nutrients` is atom-keyed in memory but string-keyed from the DB):

```elixir
%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 47}
```

Consumers that read `recipe.badges` get this string-keyed shape. The in-memory
`badges/3` (atom-keyed, atom level) is for derive-on-read use on an already-loaded
recipe.

---

## Reading & querying

### On a loaded recipe (derive on read)

```elixir
Food.recipe_nutrient_badges(recipe)          # both tiers
Food.recipe_nutrient_badges(recipe, level: :high)
Food.nutrient_badges(nutrients_tree, servings, opts \\ [])
```

### Filter recipes by badge (the point of persisting)

```elixir
Food.recipes_with_badge("Iron")             # recipes HIGH in iron (default)
Food.recipes_with_badge("Iron", "source")   # SOURCE-of-iron recipes
```

Returns an `Ecto.Query` (composable with pagination/ordering/preloads) that
matches against the persisted `recipes.badges` jsonb array via a `WHERE EXISTS
(unnest(badges) …)` fragment. No GIN index — a scan is ample at this app's scale;
revisit if a badge facet gets heavy.

---

## Surfaces (where badges appear)

### Browse filter + crawlable discovery — "foods high in iron"

The public discovery surface is a **filter on `/browse`**, not a bespoke landing
page. A chip rail under the search box exposes a curated shortlist of nutrients;
each chip is a **real, server-rendered, crawlable link** (not a client-only
toggle), so the same URL is both the in-app filter and an SEO target.

- **Route:** `localized_live("/search/nutrient/:nutrient", RecipeBrowserLive.Index,
  :index)` — sibling of the `/search/hashtag` and `/search/ingredient` routes.
  Slugs come from `Food.claim_slug/1` / `label_for_slug/1` (`NutrientClaims`,
  derived from `nrv/0`), e.g. `/search/nutrient/iron`, `/el/search/nutrient/iron`.
- **Query:** `Food.search_recipes_by_badge(label, "high", language)` — wraps
  `recipes_with_badge/2` and, unlike the hashtag/ingredient searches, **excludes
  private and image-less recipes** (it is an indexable public page). Returns
  `{query, {recipes, cursor_after}}`, feeding the browse LiveView's existing
  cursor-stream + load-more machinery (the `RecipeBrowserLive.Index` nutrient
  `apply_action/3` clause stores the query as `:query`, sets `:active_nutrient`
  for the chip highlight, and a neutral label-voice `page_title`).
- **Chips:** `RecipeBrowserLive.Index.chip_nutrients/0` — Iron, Calcium, Vitamin C,
  Potassium, Magnesium (**"high" tier only**). All 22 NRV nutrients stay reachable
  by URL for SEO long-tail; only these 5 render as chips and go in the sitemap, to
  avoid thin micronutrient pages.
- **Sitemap:** `SitemapController` emits a localized entry per chip nutrient.
- **Labels:** `MehungryWeb.NutrientLabels.claim_label/1` →
  `gettext("High in %{nutrient}", …)` over the localized nutrient name — "High in
  Iron" / "Υψηλή σε σίδηρο". **Neutral label voice only**, never medical.

### Recipe cards & detail

`MehungryWeb.RecipeComponents.high_badges/2` reads the persisted, already-gated
`recipe.badges` (string-keyed) and filters to the `"high"` tier. It is the single
helper every HTML surface uses:

- **Browse card** (`recipe_card/1`) — top 1–2 pills overlaid on the image.
- **Home feed** (`home_live/components/post_card.html.heex`) — pills right-aligned in
  the action row (beside like/comment/share), not over the image, so the photo stays
  clean; top 2.
- **Recipe detail** (`RecipeDetailsComponent`) — all high badges below the title.

All render `"High in X · N% NRV"` — the % is the auditable proof that keeps the
claim on the label side of the line. One consistent color app-wide (**paprika**,
the brand accent) so the badge is recognizable as the same element everywhere:
solid/opaque over the photo on the browse card, subtle `/15` tint on the panel
surfaces (home, detail).

### Mobile API

`Api.V1.RecipeJSON` serializes `recipe.badges` as a pass-through `badges` array on
`feed_card/3`, `detail/4`, and `card/2` (spec §4). No recompute in the controller.

---

## Backfilling existing recipes

Because the worker now writes `badges` alongside `nutrients`, **the existing
"recalculate nutrients" action is the badge backfill** — no dedicated job.

- **Prod (recommended):** admin UI → **`/professional/maintenance`** → **"Recalculate
  all"** (calls `Food.enqueue_nutrient_recalculation_for_all/0` on the live node;
  one Oban job per recipe; watch drain at `/oban`). A tracked, live-progress
  version exists on **`/professional/recipes`**
  (`Nutrients.start_full_recalculation_run/0`).
- **Dev:** `iex -S mix` → `Mehungry.Food.enqueue_nutrient_recalculation_for_all()`.
- **Not** via `bin/mehungry_umbrella eval`: `enqueue_…` uses `Oban.insert`, which
  needs the running supervision tree that a bare `eval` doesn't boot.

Deploy order: migration adds the column (defaults `[]`) → trigger a recalculation
to catch up pre-existing rows. New/edited recipes get badges automatically after.

> **After shipping the coverage gate, re-run the recalculation.** Rows badged
> before the gate existed may carry ungated (possibly over-claimed) badges;
> recomputing them applies the floor retroactively. It's the same
> `Food.enqueue_nutrient_recalculation_for_all/0` path — no new job.

---

## Known limitations (deliberately out of scope)

- **No per-serving plausibility cap.** The data-coverage gate (above) catches the
  common failure — thin/missing nutrient data. But a recipe with
  *present-but-wrong* nutrient data could still over-claim. A naive cap is risky
  (liver is genuinely ~1000%+ NRV B12), so a value-level plausibility cap is a
  considered follow-up, not shipped.
- **Cooking losses not modeled.** USDA values are used as-is; heat-labile
  nutrients (vitamin C, folate, thiamin) are in reality reduced by cooking, so
  badges on those are, if anything, generous. The stricter EU thresholds keep it
  conservative.
- **Vitamins/minerals only.** `NutrientClaims` covers the 22 Annex XIII vitamins
  and minerals; **protein and fibre** (separate Reg 1924/2006 thresholds) are not
  implemented, though they are the claims consumers search for most — a planned
  fast-follow, after which they'd lead the chip rail.
- **Greek chip label is nominative.** `"High in %{nutrient}"` interpolates the
  shared `NutrientLabels` name (nominative, "Σίδηρος"), so EL reads "Υψηλή σε
  Σίδηρος" rather than the ideal declined "…σε σίδηρο". Acceptable; per-nutrient
  declension is a polish item.

---

## Tests

- `apps/mehungry/test/mehungry/food/nutrient_claims_test.exs` — pure: thresholds,
  tree traversal, unit conversion, servings fallback, sodium exclusion, the
  **coverage gate** (below the floor → `[]`; at/above → intact; omitted/non-numeric
  `:coverage` → ungated), and `badges_for_storage/3` (incl. the atom-key JSON
  round-trip that mirrors the write path).
- `apps/mehungry/test/mehungry/food/nutrition/nutrient_calculation_test.exs` —
  `nutrient_data_coverage/1` (all/none covered, mass-weighting, 0 g drop-out, zero
  total) + `calculate_recipe_nutrition_value_with_coverage/1` guard clause.
- `apps/mehungry/test/mehungry/food/recipes_badges_test.exs` — DataCase:
  `recipes_with_badge/2` filtering, stale-badge clearing in `put_nutrient_info/2`,
  and the end-to-end write-path gate (an iron-rich recipe earns the badge above the
  coverage floor; the same recipe swamped by a data-less ingredient persists no
  badges).

## Read next

- [`nutrition_calculation.md`](nutrition_calculation.md) — how `recipe.nutrients`
  (the input to badges) is computed, stored, and read.
- [`nutrients.md`](nutrients.md) — the Nutrient data model and `Food.Nutrition.*`
  helpers (normalizer, hierarchy builder).
