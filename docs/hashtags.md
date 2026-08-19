# Hashtags

How hashtags work across Mehungry — the data model, how tags get **onto** a
recipe, and where they get **read back out** (browse/search, post cards, SEO
sitemap, social captions). Hashtags in this app are a recipe-only concept: there
is no post-level or user-level hashtag.

> The canonical schema card is [`entities/hashtag.md`](entities/hashtag.md). This
> doc is the cross-cutting *usage* map.

## Data model

Two tables, a classic many-to-many between recipes and reusable tags.

| Table | Schema | Key columns |
|---|---|---|
| `hashtags` | `Mehungry.Hashtag` (`lib/mehungry/hashtag.ex`) | `title` (unique index) |
| `recipe_hashtags` | `Mehungry.Food.RecipeHashtag` (`lib/mehungry/food/schemas/recipe_hashtag.ex`) | `recipe_id`, `hashtag_id` |

- Migrations: `20241120111737_add_hashtags_table.exs`,
  `20241120134320_add_recipe_hashtag.exs`. Both FKs `on_delete: :delete_all`;
  indexed on `hashtag_id` and `recipe_id`.
- `hashtags.title` has a **unique index**, so a tag is deduplicated by text and
  reused across recipes (this is what makes `/search/hashtag/:tag` meaningful).
- `Mehungry.Hashtag.get_hashtag_by_title/1` is the reuse lookup used everywhere a
  tag needs to be created-or-found.
- `RecipeHashtag` carries a virtual `temp_id` (form assoc plumbing) and a
  `maybe_mark_for_deletion/1` helper for `on_replace` editing. The parent
  `Recipe` declares `has_many :recipe_hashtags, on_replace: :nilify`.

## The shared reconciliation routine — `Food.ensure_recipe_hashtags/1`

`Mehungry.Food.Recipes.ensure_recipe_hashtags/1` (delegated on the `Food` facade,
`recipes.ex`) is the **one idempotent, additive routine** behind every path that
should connect a recipe to its tags. It:

1. re-parses the recipe's `description` for `#tags` (reconnect — see path 1 below),
2. runs `Mehungry.Food.DietClassifier.classify/1` over the recipe's ingredient
   **categories** to derive `#vegan`/`#vegetarian` when applicable, and
3. get-or-creates each desired `Hashtag` and inserts any missing `RecipeHashtag`
   join row.

It **never deletes** join rows or hashtags (stale tags are left to be reclaimed),
and returns `{:ok, added_count}`. `create_recipe`/`update_recipe` call it after a
successful write, so manual, AI, and bot creation all get the same treatment; the
admin reconciliation sweep calls the exact same function, so the create path and
the sweep can never diverge.

### Auto vegan/vegetarian classification (`Food.DietClassifier`)

`diet_classifier.ex` is deterministic and reuses `Food.Categories.diet_category_ids/2`
(the same excluded-category vocabulary the profile diet presets write): a recipe is
`#vegan` when none of its ingredients fall in a vegan-excluded category
(Meats/Fish/Poultry/Dairy/Pork/Sausages/Lamb/Beef) and `#vegetarian` when none fall
in the vegetarian-excluded set (same minus Dairy). Because vegan-excluded ⊃
vegetarian-excluded, a fully-plant recipe earns **both** tags. It is conservative on
unknowns: a recipe with no ingredients, or **any** ingredient missing a category,
gets no diet tag.

## How tags get onto a recipe

There are **two independent ingestion paths**, and they don't share a
normalization routine — worth knowing when debugging why a tag did/didn't attach.
Both are then reconciled by `ensure_recipe_hashtags/1` above (which also adds the
diet tags).

### 1. Manual recipes — parsed from the description string

When a user creates/edits a recipe, `Food.Recipes` extracts hashtags from the
free-text **description** (`lib/mehungry/food/recipes.ex`):

- `get_recipe_hashtags/1` → `get_hashtags_string/1` scans the description with
  `@hashtag_regex` (`~r/#([\p{L}\p{N}_-]+)/u`), extracting each `#tag` body, and
  maps each to either `%{"hashtag_id" => existing.id}` (reuse) or
  `%{hashtag: %{title: title}}` (create). The result is injected as
  `recipe_hashtags` via `Mehungry.Utils.put_map` before the changeset runs (see
  `create_recipe`/`update_recipe`, ~lines 499, 537).
- The regex strips surrounding punctuation (`#vegan,` and `(#dinner)` yield
  `vegan`/`dinner`), splits on any whitespace (not just spaces, so newline-separated
  tags work), is Unicode-aware (non-Latin tags survive), and ignores a bare `#`.
  Titles are `Enum.uniq`'d so the same tag repeated in one description can't
  double-insert or violate the unique-title index.

### 2. Recipe changeset — reuse-by-title on structured assoc input

`Recipe.changeset/2` runs `get_hashtags/1` (`schemas/recipe.ex`) over any
`"recipe_hashtags"` already in attrs: entries with a `hashtag_id` pass through;
entries carrying a nested `hashtag.title` are looked up by title and collapsed to
`%{"hashtag_id" => existing.id}` when the tag already exists. Then
`cast_assoc(:recipe_hashtags, required: false)` persists them. This is the safety
net that keeps the unique-title index from being violated.

### 3. AI-generated recipes — array → `#`-prefixed description

The AI pipeline keeps hashtags as a **separate `hashtags` array** all the way
through generation, then folds them back into the description text so path #1
picks them up on insert:

- `AI.Agents.RecipeAgent` and `AI.RecipeGenerator` both prompt for a `hashtags`
  array of **4–6 bare keywords with no `#`** and explicitly forbid hashtags in the
  `description` field.
- At assembly time each builds `hashtag_str` = `" " <> Enum.map_join(tags, " ",
  &"##{&1}")` and appends it to the description
  (`recipe_agent.ex` ~848, `recipe_generator.ex` ~457). So the persisted recipe's
  description ends with the `#tags`, and the normal description-parsing path turns
  them into `recipe_hashtags`.
- **Persona gating:** a `hashtags` array is only requested when the persona opts
  in. `AI.Bot.Persona` has `uses_hashtags` (boolean, default `false`);
  `RecipeAgent.hashtag_directive/1` and `persona_polish_hashtags/1` emit "leave the
  hashtags array empty — this voice does not use hashtags" for folksy personas
  (grandma, tavern) and only ask for tags when `uses_hashtags` is true. See
  [`ai/ai_bot_personas.md`](ai/ai_bot_personas.md).
- Preview/struct-building code paths that don't persist tags set
  `recipe_hashtags: []` (`ai/bot.ex` ~104, `oban_workers/recipe_publish_worker.ex`
  ~65).

## How tags are read back out

### Browse / search
- Route: `localized_live("/search/hashtag/:hashtag", RecipeBrowserLive.Index, :index)`
  (`router.ex` ~325) — locale-prefixed, e.g. `/en/search/hashtag/vegan`.
- `RecipeBrowserLive.Index.apply_action(:index, %{"hashtag" => …})` normalizes to a
  displayed `#tag` and calls `handle_search/2`.
- The search bar also treats a leading `#` as a **power-user prefix**: typing
  `#vegan` routes to hashtag search (leading `@` = ingredient search) via
  `Food.search_hashtag1/1`.
- Query helpers live in `Food.IngredientQueries` (delegated on the `Food` facade):
  - `search_hashtag/1` — exact-title lookup, preloads
    `recipe_hashtags: [recipe: [recipe_ingredients: :ingredient]]`.
  - `search_hashtag1/1` — strips the `#`, joins `Recipe ⋈ RecipeHashtag ⋈ Hashtag`
    on title, returns `{query, list_recipes(query)}` for cursor pagination.

### Rendering on recipe cards / posts
- `RecipeComponents.recipe_tags/1` renders each loaded hashtag via `recipe_tag/1`,
  which links to `~p"/search/hashtag/" <> title` and displays `#title`. It filters
  to hashtags actually preloaded with a title (`loaded_hashtags/1`), so it is safe
  to call on the cached recipe path even if `:hashtag` isn't preloaded
  (`recipe_components.ex` ~239–290). It's rendered on the recipe **detail** view
  (`recipe_details_component.ex`, used by both `RecipeDetailsLive` and
  `RecipeBrowserLive`'s show action). `get_recipe!` preloads
  `recipe_hashtags: [:hashtag]` so the titles/links are available.
- Home feed post cards (`home_live/components/post_card.html.heex` ~225) render
  `@post.reference.recipe_hashtags`, each linking to `/search/hashtag/<title>`.
  `Posts.get_post!`/`list_posts` preload `recipe_hashtags: [:hashtag]`.
- Home feed post cards (`home_live/components/post_card.html.heex` ~224) render
  `@post.reference.recipe_hashtags`, each linking to `/search/hashtag/<title>`.
- `Posts` preloads `recipe_hashtags: [:hashtag]` on recipe references
  (`posts.ex` ~51, 71, 149) and `Food.Recipes` preloads `recipe_hashtags: [:hashtag]`
  in its standard recipe loads (`recipes.ex` ~30).

### SEO / sitemap
- `SitemapController` selects distinct hashtags joined through `RecipeHashtag`
  and emits localized `/search/hashtag/<url-encoded-title>` entries into
  `sitemap.xml` (`sitemap_controller.ex` ~23, 110). Each tagged-recipe listing is a
  crawlable landing page. See [`seo.md`](seo.md).

### Social captions (separate, brand-level)
- Instagram captions are **not** built from recipe hashtags. `Social.Instagram.Caption`
  appends a single fixed brand tag `@hashtag "#m3hungry"` as the caption suffix
  (`social/instagram/caption.ex` ~9). This is unrelated to the `hashtags`/`recipe_hashtags`
  data model above.

## Diet mode — filtering browse/home by `#vegan`/`#vegetarian`

A user whose profile sets a Vegan/Vegetarian diet has the browse and home feeds
filtered to the matching hashtag, with a toggleable badge at the top.

- The mode is **derived from the user's persisted profile category rules** — there
  is no stored diet label. `Food.Categories.diet_mode_for_category_rules/1`
  (delegated on `Food`) reverses `diet_category_ids/2`: it returns `:vegan` when the
  user's excluded categories cover the vegan-excluded set, else `:vegetarian`, else
  `nil` (guarding against an empty/unseeded vocabulary). `Accounts.diet_mode/1`
  resolves it for a user from their `UserCategoryRule`s.
- `RecipeBrowserLive` (`recipe_browser_live/index.ex`): `mount` assigns `:diet_mode`
  (+ `:diet_mode_available`); `handle_search/2`'s default-browse (`nil` query) branch
  filters via `Food.search_hashtag1("#" <> mode)`. An explicit search (`#`/`@`/text/
  condition) overrides the mode. `toggle_diet_mode` flips it and re-runs the search.
- `HomeLive` (`home_live/index.ex`): the in-memory `all_posts` feed is filtered to
  posts whose recipe carries the mode's hashtag (`filter_by_diet/2`); `toggle_diet_mode`
  re-filters `all_posts_all` and resets the stream.
- Both render a "#vegan/#vegetarian mode on/off" badge in their template headers.

## Reconciliation sweep (admin)

Production drift (recipes not connected to the tags they should have) is repaired by
an admin sweep on **`/professional/recipes`** (`ProfessionalLive.Recipes`), built on
the Oban-UI-connected reference pattern (`docs/reference_architecture/oban_ui_connected_worker.md`):

- Durable tracking: `Mehungry.Food.HashtagReconciliation` (one row per recipe,
  `pending → processing → completed|failed`, `tags_added`), commanded/broadcast by
  `Mehungry.Food.HashtagReconciliations` (global topic, full-row terminal broadcast +
  lightweight `processing` signal).
- Worker: `Mehungry.ObanWorkers.HashtagReconciliationWorker` on the dedicated
  `hashtag_reconcile` queue (concurrency 1); one job per recipe, calls
  `Food.ensure_recipe_hashtags/1`.
- UI: the "Reconcile hashtags" button fans out one job per not-yet-completed recipe
  (`start_async`); a coalesced (400 ms flush) aggregate progress bar shows the
  pending/processing/completed/failed counts live. "Reset" clears the tracking rows.

## Bulk deletion note

Recipe cascade-delete tooling (admin `/professional/recipes`) explicitly accounts
for `recipe_hashtags` among the child rows removed with a recipe
(`professional_live/recipes.html.heex` ~228); the FK `on_delete: :delete_all` also
covers this at the DB level.

## Gotchas / observations

- **Two parsers, one goal.** Description-string parsing (`get_hashtags_string/1`)
  and structured-assoc reuse (`Recipe.get_hashtags/1`) both dedupe by title but via
  different code. Description parsing now strips surrounding punctuation and dedupes
  repeats, so `#vegan,` and `#vegan` collapse to one `vegan` tag.
- **AI tags round-trip through text.** Even though the AI keeps a clean `hashtags`
  array, it's serialized back into the description with `#` and re-parsed on save —
  so AI recipes go through the same description parser as manual ones.
- **`title` is the identity.** No slug/normalization column; case and punctuation
  in `title` are load-bearing for the unique index, search joins, and URLs.
  `Hashtag.changeset/2` now carries `validate_required(:title)` +
  `unique_constraint(:title)`, so the get-or-create race in
  `ensure_recipe_hashtags/1` surfaces a changeset error (re-read the winner) rather
  than a raw DB exception.
- **No post/user hashtags.** Despite the `Posts` context preloading them, tags are
  always a property of the referenced *recipe*, not the post itself.
