# UniTools World Recipes import (admin review)

Imports recipes from the **UniTools World Recipes** dataset
([theunitools.com](https://theunitools.com/en/data)) into the app, one at a time,
under human review. This is the third adapter over the shared, source-agnostic
`FoodData.RecipeIngredientResolver` (after MyPlate — `docs/food/myplate_import.md`
— and Gutenberg — `docs/food/gutenberg_import.md`). It mirrors the Gutenberg flow
(a single bulk document → N local recipes); the differences all stem from **two**
things:

1. **The source is already structured.** Each ingredient arrives as
   `%{name, quantity, unit, note}`, so there is no free-text parsing step — the
   decoder builds the normalized maps `RecipeIngredientResolver` documents as its
   direct input, skipping the lossy text round-trip the other two importers need.
2. **The licence is not public domain.** UniTools is **CC BY-SA 4.0**. That is a
   reuse obligation, not a free-for-all: each imported recipe must keep the
   "UniTools — theunitools.com" credit **and** carry the CC BY-SA 4.0 licence
   forward (ShareAlike). MyPlate/Gutenberg are public domain and carry no such
   obligation — this is the one structural thing UniTools adds to the pipeline.

## Dataset

501 recipes from 127 countries, bilingual (ru/en) — the importer keeps **English**
only (the app ships en/el; Russian is dropped). `FoodData.UniTools.Catalog` is the
curated manifest; each entry points at a bundled JSON file:

| id | Title | File |
|---|---|---|
| v1 | UniTools World Recipes | `priv/unitools/unitools-recipes-v1.json` |

The dataset is **bundled** under `priv/` (offline-safe, deterministic) rather than
fetched at runtime — it's a single static ~2.6 MB versioned file, so there's no
benefit to depending on the host being up. Adding a dataset is a one-line `Catalog`
entry after dropping its file in `priv/unitools/`.

## Source + licence metadata

`FoodData.UniTools.Client` (behind `FoodData.UniTools.ClientBehaviour`, swapped for
a stub in tests via the `:unitools_client` config key) reads the bundled file,
JSON-decodes it, and caches the decoded wrapper for a day (avoids re-reading on
every recipe patch). A load failure shows a distinct **"couldn't load the dataset …
Retry"** state (never "all caught up", which means every recipe was actually
reviewed).

`FoodData.UniTools.Decoder.decode/1` splits the wrapper into
`%{meta: meta, recipes: [recipe]}`:

- **`meta`** — `license`, `attribution`, `landing_page`, `name`, `version` read
  from the dataset's **own wrapper**, not hardcoded. The licence travels with the
  data, so an upstream relicensing in a future version is honoured automatically.
- each **`recipe`** — English `title`/`summary`/`native_name`, `cuisine` (mapped
  from the `country` code via the wrapper's `countries` list, e.g. `IT` →
  "Italian cuisine"), `servings`, `difficulty` (easy→1/medium→2/hard→3),
  `prep_minutes`/`cook_minutes`, resolver-ready `ingredients`, a `directions`
  list, and the pretty-printed `raw` record shown beside the form.

## Ingredients

Units pass through the resolver lowercased — it canonicalizes the aliases it knows
(`g`, `kg`, `tbsp`, `tsp`, `clove`, `slice`, `piece`…). Units it can't convert
(`ml`, `l`, `pinch`, `sprig`, `toTaste`) land in the importer's `unmatched` list
for the admin to fix by hand. `UniToolsImporter.build_recipe_attrs/3` seeds each
matched ingredient's `unit_selection` so the review form's unit dropdown shows the
resolved choice (positive = measurement unit, negated = description-only USDA
portion), exactly as MyPlate/Gutenberg do.

## Photos — not imported

UniTools photos are Wikimedia Commons images under a **wide mix** of per-image
licences (GFDL, KOGL, assorted CC variants, some all-rights-reserved). Rather than
vet each, `image_url` is left nil and the app's own cover-image generation / manual
upload fills it in.

## Nutrition — recomputed

UniTools' per-serving nutrition is discarded; `Food.create_recipe/1` recomputes
`nutrients`/`badges` from the matched ingredients (`RecipePutNutrientsWorker`),
keeping these recipes consistent with the rest of the app.

## Licence handling (CC BY-SA 4.0)

Every saved UniTools recipe is stamped with:

- `source: "unitools"` — provenance marker for group management.
- `author` — `"UniTools — theunitools.com (CC BY-SA 4.0)"`, shown as the Steps-tab
  "Source" credit.
- `original_url` — the dataset landing page.
- `license` — the licence string (a dedicated `recipes.license` column added by
  `20261024192000_add_license_to_recipes`). It is rendered as a visible **"Licensed
  under CC BY-SA 4.0"** notice next to the Source credit (`recipe_source/1` in
  `recipe_components.ex`). This is what satisfies ShareAlike's visible-licence
  requirement. The column is nil for public-domain (MyPlate/Gutenberg) and in-app
  recipes.

Because the shared `RecipeFormComponent` doesn't render/submit
`source`/`author`/`original_url`/`license`/`private`, the review LiveView **re-injects**
them into the params at save (`Map.merge(provenance)` + `private`), exactly as the
Gutenberg review does — otherwise `create_recipe/1` would persist the recipe public,
untagged, and unlicensed.

## Review flow

`MehungryWeb.ProfessionalLive.UniToolsReview` (`/professional/unitools-review[/:dataset_id[/:index]]`,
admin-gated under the `:default2` session) has two modes:

- **picker** — a card per catalogued dataset with saved/skipped counts and a
  "Browse recipes" link.
- **list** (`/unitools-review/:dataset_id`) — a **fuzzy-searchable list of every
  decoded recipe** in the dataset (title + a `completed`/`skipped` badge per
  reviewed recipe), the **primary way to pick what to import** — not a blind
  "next recipe". Ranking via `MehungryWeb.ProfessionalLive.ImportReviewSearch`
  (shared with MyPlate/Gutenberg: substring + per-word `String.jaro_distance/2`,
  AND across terms). Clicking a row opens it for review.
- **review** (`/unitools-review/:dataset_id/:index`) — the decoded recipe loaded
  into the real `RecipeFormComponent` (editable) beside the verbatim dataset JSON,
  with **Publish on save** (default off → staged `private: true`), **Save** (create
  + return to the list, badge updated) and **Skip** ("pass for now", also returns
  to the list).

Imports are **staged private** by default so an ingredient-matching sweep doesn't
dump half-curated recipes into public browse. Per-recipe outcomes persist in
`unitools_imports` (`FoodData.UniTools.{ImportRecord, Imports}`, keyed on the ref
`"<dataset_id>:<index>"`) so review resumes across sessions and per dataset.

## Group management

Every saved import carries `recipes.source = "unitools"`, so the batch is
group-manageable via the source-generic
`Food.{count_recipes_by_source, recipe_ids_by_source, delete_recipes_by_source}/1`,
surfaced as a **"Delete UniTools imports (N)"** admin action on
`/professional/recipes` (next to the MyPlate/Gutenberg ones).
