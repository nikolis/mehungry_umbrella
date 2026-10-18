# Translation gates — nutrient names & the ingredient picker

Two **single chokepoints** that localize whole families of UI surfaces at once, so
a new page that renders a nutrient breakdown or an ingredient search box is
localized *for free* instead of needing its own fix. This is the companion to
`docs/localization.md` (the locale plumbing: `/el/…` URLs, `SetLocale`,
`RestoreLocale`, Gettext vs `*_translation` tables) — read that first for how the
locale reaches a render.

Supported locales: **`en`** (default, source) and **`el`**.

---

## Why "gates" and not per-site fixes

Before this, nutrient names and the calendar ingredient search rendered in English
even under `/el/…`, and each surface would have needed its own patch. Instead:

- **Every full nutrient breakdown already funnels through one component**
  (`NutritionAccordion`). Localize there → recipe pages, the `/foods/:slug` species
  page, the calendar daily detail, and the calendar "View Recipe" modal are all
  covered by one change.
- **Every ingredient picker uses the same widget** (`SelectComponentDeep`) with a
  pair of search/label closures. Centralize the locale-aware closures → recipe
  creation and the calendar meal form share one implementation.

---

## Gate 1 — nutrient display names

### The vocabulary is UI text, not `Nutrient.name`

The crucial, non-obvious fact: the names shown in a breakdown are **not** the raw
`Mehungry.Food.Nutrient.name` values. `Food.NutrientCalculation.nutrient_tree/1`
keys its map on:

1. a normalized, code-defined vocabulary from
   `Food.NutrientNameNormalizer.normalize/1` (~45 canonical strings — "Energy",
   "Total Fat", "Vitamin B12", …), **plus**
2. synthetic grouping nodes from `Food.NutrientHierarchyBuilder` ("Vitamins",
   "Minerals", "Dietary Fiber", "Complex Carbohydrates", …) that have **no backing
   `Nutrient` row at all**, **plus**
3. individual fatty acids rewritten at render time by
   `Food.Nutrition.FattyAcidMatcher.resolve_names/1` ("Oleic acid (C18:1,
   Omega-9)").

> ⚠️ Therefore the DB `nutrient_translations` table (keyed on raw `Nutrient.name`,
> curated at `/professional/translations`) is the **wrong vocabulary** for this
> display surface — it would miss every grouping node and most canonical names. It
> is deliberately **not** used here. Nutrient display labels are translated with
> **Gettext** instead, which also gives automatic per-string English fallback.

### `MehungryWeb.NutrientLabels` — the one source of the vocabulary

`apps/mehungry_web/lib/mehungry_web/components/nutrient_labels.ex`

- `@vocabulary` — the full set of non-fatty-acid display names (every distinct
  `Nutrient.name` run through the normalizer + the synthetic group nodes + short
  macro labels). One `gettext/1` clause per entry is generated from this list so
  `mix gettext.extract` discovers them.
- `translate_name/1` — localizes a single name via the `gettext` macro under the
  current process locale; unknown names (incl. the individual fatty-acid common
  names, which we intentionally **leave in English**) fall through unchanged — always
  safe to call on any nutrient name.
- `translate_names/2` — recurses a nutrient node / list / `name => node` map under
  `Gettext.with_locale/2`, calling `translate_name/1` per node and recursing into
  `children` (mirrors `FattyAcidMatcher.resolve_names/1`); no-op for the source
  locale. **Deliberately not memoized** — an earlier per-locale `:persistent_term`
  cache went stale when the `.po` changed under a long-running node (the cache key
  can't see translation edits), so the breakdown rendered English while the live
  `gettext`-macro paths (highlight cards, calendar pie) rendered Greek. The map is
  tiny and `gettext` is fast, so it's recomputed per render.

Greek strings live in `apps/mehungry_web/priv/gettext/el/LC_MESSAGES/default.po`.
After adding a vocabulary entry: `cd apps/mehungry_web && mix gettext.extract &&
mix gettext.merge priv/gettext`, then fill the `el` `msgstr`.

### The chokepoint: `NutritionAccordion`

`apps/mehungry_web/lib/mehungry_web/components/nutrition_accordion.ex`

`nutrition_accordion/1` has a `locale` attr and applies the translation as the
**last** pass of its pipeline:

```
sort_by(priority)  →  FattyAcidMatcher.resolve_names()  →  NutrientLabels.translate_names(locale)
```

Order matters: fatty-acid nodes arrive as raw `"MUFA 16:1"` and `resolve_names`
overwrites `name` with the English display string, so translating **after** means we
key on the final, stable string (and fatty acids simply aren't in the map → stay
English).

> Never translate inside the domain `nutrient_tree/1`: that map is persisted to the
> `nutrients` jsonb column and merged/priority-sorted by **English** keys
> (`NutrientUtils.summarize_meals_nutrients/1`). Localization is display-time only.

### Threading `locale` into the accordion call sites

| Surface | File | How locale arrives |
|---|---|---|
| Recipe detail (+ calendar "View Recipe", same component) | `recipe_components.ex` `recipe_nutrients/2` → `tabs_component.ex` → `RecipeDetailsTabsConfig` | `RecipeDetailsComponent` derives it from `Gettext.get_locale(MehungryWeb.Gettext)` (process locale set by `RestoreLocale`) — avoids threading through 5+ modal mount sites |
| `/foods/:slug` species page | `species_detail_live/index.html.heex` | `locale={assigns[:current_language] || "en"}` |
| Calendar daily detail | `calendar_live/calendar/widget.ex` | `recipe_nutrients(@recipe, assigns[:current_language] || "en")` |
| AI recipe review (admin) | `professional_live/ai_bot_live/recipe_review.ex` | `locale="en"` (English-only tool) |

### Secondary surfaces (don't pass through the accordion)

Localized via the **same** `NutrientLabels`/Gettext source, kept proportional:

- Species "Nutritional Highlights" cards (`species_detail_live`) — `translate_name/1`.
- Calendar macro pie labels (`widget.ex` `build_macro_slices/1`) — `translate_name/1`.
- Calendar summary badge words (`widget.ex` `summary_tags/1`) — `gettext`/`ngettext`.

**Deferred** (low-visibility, English for now): the calendar micro-nutrient pie
legend (`clean_label/1`), the PieChart tooltip title, the "Macros" heading.

---

## Gate 2 — the ingredient picker

### `MehungryWeb.IngredientSearchFns`

`apps/mehungry_web/lib/mehungry_web/live/ingredient_search_fns.ex`

`search_fns(language, owner_id)` returns `%{item_fn, label_fn, get_by_id_fn}` — the
locale-aware closures for `SelectComponentDeep`:

- **`"el"`** → `Food.IngredientSearch.search_in_language/3` (accent-insensitive
  Greek search over `ingredient_translations`), labels by the translated name, and
  `get_by_id_fn` overlays the Greek name via `Food.find_ingredient_translation/2`.
- **else** → English base-name `Food.IngredientSearch.search/3` + `remove_parenthesis`.

Depends on existing `ingredient_translations` rows (legacy `"Gr"` code) — the same
data that powers recipe creation, so no new data step.

### Consumers

Both pickers call `search_fns/2` through the identical `SelectComponentDeep`:

- Recipe creation — `create_recipe_live/ingredient_component.ex` (`assign_search_fns/1`).
- Calendar meal form — `current_language` is threaded
  `CalendarLive.Index` → `MealFormComponent` → `CalendarLive.Components` →
  `components/ingredient_user_meal.html.heex`, which calls `search_fns/2`.

> Do **not** push this into `SelectComponentDeep` — it's a generic select widget;
> the food-domain knowledge belongs in the helper.

---

## REST API (`/api/v1`) parity

The mobile API localizes the **same** surfaces through the **same** functions (per
`docs/new_dec_specs/mobile_api_spec.md` §Language). Locale is resolved per request by
`MehungryWeb.Api.V1.Locale.resolve/2` (explicit `?lang=` → `Accept-Language` → user
profile → `en`).

- **Nutrient trees** (recipe detail `GET /recipes/:id`, daily nutrition
  `GET /meals/day/:date/nutrition`): serializers call
  `MehungryWeb.Api.V1.JSON.Helpers.localize_nutrients/2`, which resolves fatty acids
  (`FattyAcidMatcher`) then applies `NutrientLabels.translate_tree/2` — translating the
  `name => node` map's **keys and node names** (the stored map is keyed by display
  name). Recipe detail threads locale via the `ctx` map.
- **Ingredient search** (`GET /ingredients/search?source=local`): the controller
  branches on locale to the same `Food.IngredientSearch.search_in_language/3` the
  calendar picker uses for `el`.
- **Compound names** (`GET /species/:slug`): the controller overlays
  `Food.compound_display_names/2`, same as the web species page.

So a nutrient map is localized once per layer: the web accordion walks a **list** of
nodes (`translate_names/2`); the REST serializer translates the **keyed map**
(`translate_tree/2`). Both share the one vocabulary in `NutrientLabels`.

## Adding a new nutrient-rendering or ingredient-search surface

1. **Nutrient breakdown:** render through `NutritionAccordion.nutrition_accordion/1`
   and pass `locale`. If you show a nutrient label *outside* the accordion, call
   `MehungryWeb.NutrientLabels.translate_name/1`. Add any new display string to the
   `@vocabulary` + a `translate_name/1` clause, then re-extract/merge Gettext.
2. **Ingredient picker:** build the `SelectComponentDeep` closures from
   `MehungryWeb.IngredientSearchFns.search_fns(language, owner_id)` — never hardcode
   `IngredientSearch.search/3`.

See the implementation plan at
`~/.claude/plans/when-language-is-seted-stateless-hearth.md`.
