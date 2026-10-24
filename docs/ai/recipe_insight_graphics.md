# Recipe Insight Social Graphics

Generates eye-catching, shareable social-media graphics from an existing recipe:
the recipe's real photo composited with a deterministic insight overlay — a
macronutrient donut + a "Rich in <family>" / condition / macro badge, the
AI-written headline, and the m3hungry wordmark.

**Hybrid by design.** The *data* (donut proportions, gram labels, calorie count)
is drawn deterministically from the recipe's computed nutrition so it is always
truthful; only the **headline + caption** come from AI. Generative image models
are never used to draw the numbers (they render charts/figures unreliably).

## Pipeline

`MehungryWeb.RecipeSocialGraphicWorker` (Oban `:ai_agents` queue, lives in the
web app because it drives the web-only renderer):

1. **Select** — `Mehungry.AI.RecipeInsight.candidates/1` ranks the recipe's most
   differentiated characteristics from data we already compute:
   `compound` (via `Food.compounds_for_recipe/1`, polyphenols first; the generic
   `"other"` family is excluded) → `health` (`Health.flags_for_recipe/2`,
   `"encourage"` only) → `macro` (per-serving high-protein / low-cal / high-fiber
   thresholds) → `balanced` fallback. `macros/1` reads the cached `recipe.nutrients`
   jsonb (`Energy`/`Protein`/`Total Fat`/`Carbohydrates`, divided by `servings`).
2. **Caption** — `Mehungry.AI.InsightCaptioner.generate/2` (the quota-metered AI
   step, via `AI.Client`) picks the single best candidate and writes a `headline`
   (drawn on the card) + `caption` (post copy). `fallback/2` produces both
   deterministically from the top candidate if the AI call fails.
3. **Render** — `MehungryWeb.InsightGraphic.render/2` (`:image`/`vix` + an SVG
   overlay rasterised via `svgload`) → 1080×1080 JPEG binary.
4. **Store** — `Mehungry.Storage.put/3` → public URL.
5. **Persist** — a `Food.RecipeSocialGraphic` row (`recipe_social_graphics`:
   `image_url`, `insight_type`, `headline`, `caption`); newest is what the share
   UI offers.
6. **Meter + broadcast** — `Subscriptions.record_usage/2` on success; PubSub on
   `recipe_social_graphic:<id>` so the triggering LiveView swaps spinner → card.

## Gating

AI feature key `"graphic_generation"` in `Subscriptions.@monthly_limits`
(free 0 / m3hungry_plus 10 / pro 30) and the `ai_usage` changeset whitelist.
`check_quota/2` at the trigger, `record_usage/2` on worker success; owner email
bypasses.

## Surfaces

- **Admin** — per-row "Make graphic" on `/professional/recipes`
  (`ProfessionalLive.Recipes`); result preview + download link.
- **Per-user** — "Shareable graphic" button on `RecipeDetailsComponent`
  (quota-gated), generated in-component via `start_async`; stored graphic +
  download link.

## Posting the graphic to social

When a recipe has a generated insight graphic, the manual share flow posts the
**graphic** instead of the plain cover. `Food.recipe_with_share_image/1` swaps the
recipe's `image_url` to the newest `RecipeSocialGraphic.image_url` (unchanged if
none exists); `SocialMediaPostComponent` (Facebook / Instagram / Pinterest) and
`RecipeDetailsComponent`'s direct post handlers call it before handing the recipe
to the platform clients. The post caption is unchanged (still the recipe caption);
only the image is swapped. The bot pipeline (`Social.Publisher`) still posts the
cover.

## Known constraints

- The renderer needs the libvips build to support `svgload` (rsvg) + font
  rendering. Verified locally; the **prod release render must be smoke-tested**
  (bare-Alpine runtime uses vix's bundled libvips).
- **Deferred:** using the AI caption (not just the image) in the social post;
  feeding the graphic into the bot `Social.Publisher` pipeline;
  population-relative "differentiation" stats; a mobile `/api/v1` endpoint.
