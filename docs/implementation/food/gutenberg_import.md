# Project Gutenberg recipe import (admin review)

Imports recipes from **public-domain, English-language** cookbooks on
[Project Gutenberg](https://www.gutenberg.org) into the app, one at a time, under
human review. Every catalogued title is old enough to be public domain worldwide,
so — like the USDA MyPlate corpus (`docs/food/myplate_import.md`) — we may store,
serve, and build on these recipes indefinitely, with a voluntary source credit.

This is the second adapter over the shared, source-agnostic
`FoodData.RecipeIngredientResolver` (the first is MyPlate). It mirrors the MyPlate
flow closely; the differences all stem from the source being an **unstructured
book** rather than a per-recipe JSON API.

## Catalogue

`FoodData.Gutenberg.Catalog` is the curated list of importable books. Each entry
carries the `:format` the parser needs:

| ebook | Title | Author | Cuisine | Format |
|---|---|---|---|---|
| 24407 | The Italian Cook Book | Maria Gentile | Italian | `:numbered` |
| 6385 | Simple Italian Cookery | Antonia Isola | Italian | `:heading` |
| 43912 | Practical Italian Recipes for American Kitchens | Julia Lovejoy Cuniberti | Italian | `:heading` |

Only books whose structure has been validated against one of the two parser
formats are listed. Other English public-domain cookbooks exist on Gutenberg
(Escoffier, *The Cook's Decameron*, *Allied Cookery*, …) but use
table-of-contents / page-number layouts that need bespoke parsing first — adding
one is a one-line `Catalog` entry **after** confirming its layout, never before.

## Source

`FoodData.Gutenberg.Client` (behind `FoodData.Gutenberg.ClientBehaviour`, swapped
for a stub in tests via the `:gutenberg_client` config key) downloads the whole
book as plain UTF-8 text (`…/cache/epub/{id}/pg{id}.txt`). A book is one
~100–200 KB document, so a single download serves an entire review session; the
text is static, so it's cached for a day (polite to Gutenberg, avoids re-fetching
on every recipe patch). Transient failures (network / 5xx) retry with backoff; a
genuine load failure shows a distinct **"couldn't load the book … Retry"** state
(never "all caught up", which means every recipe was actually reviewed).

## How a recipe is built

Two steps turn one book into `Recipe` attrs:

1. **`FoodData.Gutenberg.BookParser`** splits the book text into recipe blocks
   using the book's `:format` — the Gutenberg analogue of the MyPlate API's
   per-recipe JSON. It strips the Gutenberg license boilerplate and the book's
   own index/front-matter, then:

   - `:numbered` — blocks delimited by a lone number line; title is the next
     line, the rest is prose directions (these books list ingredients *inside*
     the prose, so `ingredient_lines` is usually `[]`).
   - `:heading`  — blocks delimited by an ALL-CAPS title line; an optional
     italic original-language subtitle and an **indented** ingredient list lead
     the prose. ALL-CAPS headings with an empty body (section labels like
     `SOUPS`) are dropped.

   Extraction is deliberately **best-effort** — a century-old book's layout is
   far looser than a JSON API — because the flow is human-in-the-loop (see
   below). Output per recipe: `%{index, title, subtitle, ingredient_lines,
   directions, raw}`.

2. **`FoodData.GutenbergImporter.build_recipe_attrs/3`** maps one parsed block +
   its `Catalog` entry into `Recipe` attrs. Each free-text ingredient line is run
   through the same generic `FoodData.MyPlate.IngredientParser` and then the
   shared `RecipeIngredientResolver`; unmatched lines are returned (never dropped)
   for the reviewer to fix. ALL-CAPS titles are presented Title-Cased; the
   directions become sentence-sized `steps`.

`build_recipe_attrs/3` **always** returns `{:ok, attrs, unmatched}` (even with
zero matched ingredients) so the review form can present whatever was resolved.

### Ingredients are often empty — by design

`:numbered` books (and some `:heading` recipes) write ingredients inline in the
prose, so there's no list to extract. That's expected: the recipe still imports
with its directions, and the **reviewer adds the ingredients by hand** in the
form.

### Nutrition

Not imported (these books predate nutrition labelling). `Food.create_recipe/1`
recomputes `nutrients`/`badges` from the matched ingredients
(`RecipePutNutrientsWorker`), so these recipes stay consistent with the rest of
the app.

## Attribution (public-domain credit)

Reuse is credited even though it isn't legally required: the book title + author
go into the recipe's `author` (e.g. *"Simple Italian Cookery by Antonia Isola —
Project Gutenberg (public domain)"*), and the Gutenberg landing page
(`https://www.gutenberg.org/ebooks/{id}`) into `original_url`.
`RecipeComponents.recipe_steps/1` renders a visible **"Source"** link from
`original_url` on the Steps tab.

## Review UI (admin, human-in-the-loop)

`MehungryWeb.ProfessionalLive.GutenbergReview`, mounted in the `:default2` admin
live_session (admin-gated by `MehungryWeb.AdminAuthLive`). Linked from
`/professional/recipes` ("Review Gutenberg imports"). Two modes:

- **Picker** (`/professional/gutenberg-review`) — the catalogued books with their
  saved/skipped counts and a "Browse recipes" link into each.
- **List** (`/professional/gutenberg-review/:book_id`) — a **fuzzy-searchable list
  of every parsed recipe in the book** (title + a `completed`/`skipped` badge per
  reviewed recipe), which is the **primary way to pick what to import** — not a
  blind "next recipe". The search box ranks via
  `MehungryWeb.ProfessionalLive.ImportReviewSearch` (shared with MyPlate/UniTools:
  substring + per-word `String.jaro_distance/2`, AND across terms). Clicking a row
  opens it for review.
- **Review** (`/professional/gutenberg-review/:book_id/:index`) — two columns:
  - **Left** — the matched recipe in the **same `MehungryWeb.RecipeFormComponent`**
    the Create Recipe page uses (fully editable, unmatched lines listed). The form
    bubbles its events (validate / save / add+remove rows / image upload /
    ingredient picker) to the LiveView.
  - **Right** — the **verbatim book excerpt**, so the admin can compare and fix
    before saving.

Controls: **Save** creates the recipe (via the normal form save →
`Food.create_recipe/1`), records the recipe ref `completed`, and returns to the
recipe list (badge updated). **Skip** records it `skipped` and likewise returns to
the list.

### Staged private until curated

Imports are **staged private** (`recipes.private = true`) so a quick
ingredient-matching sweep doesn't dump half-curated century-old recipes straight
into public browse. A per-recipe **"Saving as private / Publishing on save"**
toggle (default private) lets the admin publish a recipe once it's actually
curated — `private` is set from that toggle at save. (Already-saved private
imports can also be published later via the normal recipe edit path.)

Because the shared `RecipeFormComponent` only renders a recipe's editorial fields
(title, description, times, servings, ingredients), it does **not** submit
`private`, `source`, `author`, or `original_url`. The LiveView therefore
**re-injects** those at save time — without that, `create_recipe/1` (which builds
its changeset purely from the submitted params) would save the recipe public and
untagged, breaking both the private-staging guarantee and group management by
source.

## Resume state

The unit of work — the Gutenberg analogue of a MyPlate slug — is a recipe **ref**
`"<book_id>:<index>"` (e.g. `"6385:12"`). Per-ref outcomes persist in the
`gutenberg_imports` table (`FoodData.Gutenberg.ImportRecord` +
`FoodData.Gutenberg.Imports`), status `completed` or `skipped`. The list badges
each reviewed recipe (via `Imports.statuses_for/1`) so review resumes per book
across sessions — the admin picks the next one from the list. A specific recipe
can also be opened directly by index; an already-reviewed one shows a badge.

## Group management

Every saved import is marked `recipes.source = "gutenberg"`, so the batch is
group-manageable via the shared, source-generic
`Food.{count_recipes_by_source, recipe_ids_by_source, delete_recipes_by_source}/1`
— surfaced as a "Delete Gutenberg imports (N)" admin action on
`/professional/recipes` (exactly like the MyPlate batch).

## Not covered

- **Localization**: recipes import as English/imperial. Run them through the
  existing `AI.RecipeTranslator` pipeline for Greek.
- **Images**: these books ship no usable recipe photos, so imported recipes have
  no cover image until the admin uploads one in the form (or the cover-image AI
  pipeline runs).
- **Servings / times**: the books carry none; times default to 0 and servings is
  left blank for the admin to fill.
