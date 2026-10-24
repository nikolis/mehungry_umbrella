# MyPlate recipe import (admin review)

Imports recipes from the **USDA MyPlate Kitchen** collection (~1,072 recipes) into
the app, one at a time, under human review. These are U.S. federal works in the
**public domain** (17 USC §105), so — unlike the Spoonacular path, whose TOS
forbids persisting recipe data — we may store, serve, and build on them
indefinitely, with attribution.

## Source — the Internet Archive (not the live API)

The recipes are USDA public domain, but the live mirror at `myplate.food` caps
full-recipe fetches at **100/day per IP** and forbids catalog replication without a
license — a term of *its service*, independent of the content's copyright status.
So we **don't** use that API. The original `myplate.gov` (retired 2026-01-07) is
preserved by the **Internet Archive**, which merely hosts the public-domain pages
— no daily cap, no replication clause, and the *original* USDA images.

`FoodData.MyPlate.Client` (behind `FoodData.MyPlate.ClientBehaviour`, stubbed in
tests via the `:myplate_client` config key) sources entirely from the Archive:

- **`list_slugs/0`** — the corpus is static and a live CDX wildcard enumeration
  takes ~50s, so the slug list ships as a bundled manifest
  **`priv/myplate/slugs.json`** (~1,100 public-domain recipe *identifiers*, not
  content), read instantly. `Client.cdx_slugs/0` is the live CDX-API fallback /
  regenerator.
- **`fetch_recipe/1`** — fetches the closest pre-retirement capture directly from
  playback (`https://web.archive.org/web/{hint}id_/https://www.myplate.gov/recipes/{slug}`;
  Wayback redirects to the nearest capture, followed). It deliberately skips the
  `archive.org` availability API, which is throttled harder than playback.

### Parsing: JSON-LD metadata + HTML body

The archived page's schema.org **Recipe JSON-LD carries only metadata** (name,
`recipeYield`, image, nutrition, author) — the **ingredients and directions are in
the Drupal HTML body**, not the structured data. So the client:
- reads name/yield/image/description/author from the JSON-LD, and
- parses **ingredients** (`ul.ingredients li.field__item`, with `span.notes`
  → the ingredient `note`) and **directions** (`.field--name-field-instructions`
  list items, joined into a paragraph) from the markup with **Floki**.

The result is the *same shape* the importer already consumes
(`%{"name", "yield", "ingredients" => [%{"text", "note"}], "directions",
"image_url", "source_url", "contributor"}`), so nothing downstream changed.

### Resilience

`request/3` retries transient failures (network errors, 5xx, short 429 throttles)
with backoff. A long `Retry-After` is surfaced as `{:error, {:rate_limited, s}}`
(the review UI shows a "resets in ~Nh / Retry" state) rather than blocking. If the
slug list itself can't load, the UI shows a distinct **"couldn't load … Retry"**
state — never "all caught up" (which means every recipe was actually reviewed).

## How a recipe is built

`FoodData.MyPlateImporter.build_recipe_attrs/2` is a thin adapter — the ingredient
matching lives in the shared, source-agnostic **`FoodData.RecipeIngredientResolver`**
(the same engine `FoodData.SpoonacularImporter` uses). The one MyPlate-specific
step is that ingredients arrive as free text, so each line is parsed first:

1. **`FoodData.MyPlate.IngredientParser`** splits `"1 1/2 cups whole wheat flour"`
   into `%{name, quantity, unit, original}` — handling integer / decimal / simple,
   mixed, and unicode fractions, numeric ranges (lower bound), unit-vs-count
   detection, and folding the `note` into the display text only (not the search
   name).
2. **`RecipeIngredientResolver`** resolves each parsed line against existing
   ingredients / measurement units / USDA description portions. Lines that can't be
   matched are returned in an `unmatched` list — **never dropped silently**; the
   review UI surfaces them so the admin can resolve them by hand.

`build_recipe_attrs/2` **always** returns `{:ok, attrs, unmatched}` (even with zero
matches) so the review form can present whatever was resolved. Each matched
ingredient is seeded with a `unit_selection` so the form's unit dropdown shows the
resolved choice. Field mapping: `name`→title, `yield`→servings, `image_url`,
`directions`→sentence-sized `steps`, prep/cook times default to 0 (MyPlate has
none). **Nutrition is not imported** — `Food.create_recipe/1` recomputes
`nutrients`/`badges` from the saved ingredients (`RecipePutNutrientsWorker`), so
these recipes stay consistent with the rest of the app.

## Attribution (public-domain credit)

Reuse is credited: `contributor` → the recipe's `author`
(e.g. *"… — USDA MyPlate (public domain)"*), and `source_url` → `original_url`.
`RecipeComponents.recipe_steps/1` renders a visible **"Source"** link from
`original_url` on the Steps tab for any imported recipe (app-authored recipes have
no `original_url` and show nothing).

## Review UI (admin, human-in-the-loop)

`MehungryWeb.ProfessionalLive.MyPlateReview` at **`/professional/myplate-review`**
(and `/myplate-review/:slug`), mounted in the `:default2` admin live_session so it
is admin-gated by `MehungryWeb.AdminAuthLive`. Deliberately **not** part of the
user-facing Create Recipe page — it is an internal curation tool. Linked from
`/professional/recipes` ("Review MyPlate imports").

**Landing surface — the searchable recipe list.** `/professional/myplate-review`
(no slug) is a **fuzzy-searchable list of the whole slug corpus** (humanized
titles + a `completed`/`skipped` badge per reviewed slug), which is the **primary
way to pick what to import** — not a blind "next recipe". The search box ranks via
`MehungryWeb.ProfessionalLive.ImportReviewSearch` (shared with Gutenberg/UniTools:
substring + per-word `String.jaro_distance/2`, AND across terms). The list does
**not** fetch any recipe (so it never burns the daily cap); clicking a row opens
`/myplate-review/:slug`, which fetches that one recipe into the review form.

Opening a slug is the two-column review screen:

- **Left** — the matched recipe loaded into the **same `MehungryWeb.RecipeFormComponent`**
  the Create Recipe page uses: fully editable, with unmatched ingredient lines
  listed (reusing the component's `spoonacular_unmatched` display). The form
  bubbles its events (validate / save / add+remove ingredient & step rows / image
  upload / ingredient picker) to the LiveView, which copies those handlers from
  `CreateRecipeLive.Index`.
- **Right** — the **raw archived source** (the parsed recipe payload), so the
  admin can compare and fix differences before saving.

Controls: **Save** creates the recipe (via the normal form save → `Food.create_recipe/1`),
records the slug `completed`, and returns to the recipe list (where the badge now
reflects the outcome). **Skip** ("pass for now") records the slug `skipped` and
likewise returns to the list.

## Resume state

Per-slug outcomes persist in the `myplate_imports` table
(`FoodData.MyPlate.ImportRecord` + `FoodData.MyPlate.Imports`), status `completed`
or `skipped`. The list badges each reviewed slug (via `Imports.statuses_by_slug/0`)
so review resumes across sessions — the admin picks the next one from the list. A
specific slug can also be opened directly by URL; an already-reviewed slug shows an
"already completed/skipped"
badge.

## Not covered

- **Localization**: recipes import as English/imperial. Run them through the
  existing `AI.RecipeTranslator` pipeline for Greek.
- **Images**: the original USDA image CDN is dead post-retirement and the Wayback
  image proxy is unreliable, so imports carry **no image** — `create_recipe/1`
  queues an AI cover instead (or the admin uploads one in the review form). Never
  myplate.food's copyrighted remaster.
