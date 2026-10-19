# SEO Guide for M3Hungry

This document explains what SEO is, why it matters, and exactly how it works in this codebase — so you can understand, extend, and monitor it without needing prior SEO experience.

> 🚫 **NOTICE (2026-10-19): condition pages (`/conditions/:id`) are no longer part of the
> project.** Targeting dietary advice at named medical conditions turns the product into a
> **regulated medical device** (EU MDR / SaMD), which we **cannot support for now**. All
> condition-page SEO work and any "condition query" growth opportunity are **off the roadmap** —
> see the full notice under [Condition pages](#condition-pages-conditionsid). Historical
> condition content in this doc is retained for record only.

---

## What is SEO and why does it matter?

**SEO (Search Engine Optimization)** is the practice of making your website appear in search engine results when people search for relevant terms.

When someone types "vegan pasta recipes" into Google, Google runs a program called **Googlebot** that has already visited your site and built an index of your pages. The quality and quantity of information you provide to that crawler determines:

1. **Whether your pages get indexed at all** — can Google even find them?
2. **How they appear in results** — the title, description snippet, and rich features (like star ratings or cooking times)
3. **How high they rank** — relevance, content quality, and technical correctness

For M3Hungry, the highest-value SEO opportunity is individual recipe pages and hashtag category pages — someone searching "chicken tikka masala recipe calories" could land directly on that recipe page.

---

## How search engines work (the basics)

### 1. Crawling

Googlebot is a program that browses the web like a user, but automatically. It:
- Starts from known URLs (your sitemap, links from other sites)
- Follows `<a href="...">` links it finds on pages
- Visits each URL, downloads the HTML, and processes it
- Respects `robots.txt` — a file that tells it what not to visit

### 2. Indexing

After crawling, Google stores your page's content in its index — a massive database. For a page to appear in search results, it **must** be in the index.

Pages are **not indexed** if:
- They have `<meta name="robots" content="noindex">` — you explicitly told Google not to
- They returned an error (404, 500)
- The content was thin or duplicate
- The site blocked crawling in `robots.txt`

### 3. Ranking

When someone searches, Google picks the best pages from its index. Ranking factors include:
- **Relevance**: does your page's title, description, and content match the query?
- **Authority**: do other reputable sites link to yours?
- **Technical quality**: fast load time, mobile-friendly, valid HTML
- **Rich content**: structured data (JSON-LD) that Google can interpret

---

## What we implemented

### 1. `robots.txt` — telling crawlers what to visit

**File**: `apps/mehungry_web/priv/static/robots.txt`

```
User-agent: *
Disallow: /profile
Disallow: /basket
Disallow: /calendar
...
Allow: /browse
Allow: /search
Sitemap: https://www.m3hungry.com/sitemap.xml
```

**What it does**: Every crawler that visits your site first checks `/robots.txt`. The `Disallow` lines tell bots to skip those pages entirely. The `Sitemap` line tells them where to find the list of all your pages.

**Why private pages are disallowed**:
- `/profile`, `/basket`, `/calendar`, `/create_recipe` are only useful when logged in. They have no SEO value and waste Googlebot's "crawl budget" (the number of pages Google will crawl per day).
- You don't want user profile pages appearing in Google results — it's a privacy concern.

**Important**: `robots.txt` is public — anyone can read it. It's a polite instruction, not a security measure. Never put sensitive information in `robots.txt`.

---

### 2. `sitemap.xml` — a map of all your content

**File**: `apps/mehungry_web/lib/mehungry_web/controllers/sitemap_controller.ex`

**Route**: `GET /sitemap.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://www.m3hungry.com/browse/42</loc>
    <lastmod>2024-03-15</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
  ...
</urlset>
```

**What it does**: A sitemap is a list of every URL you want indexed. Without a sitemap, Google discovers your pages only by following links — it might miss thousands of recipe pages. With a sitemap, you hand Google the complete list directly.

**How it works in code**:

The `SitemapController.index/2` function:
1. Queries all non-private recipes from the database
2. Queries the top 200 hashtags (those used on more than 1 recipe)
3. Builds an XML string with all URLs
4. Returns it with `Content-Type: application/xml`

The controller runs a live database query every time the sitemap is requested. This means it always reflects the current state — new recipes appear in the sitemap immediately.

**To submit your sitemap to Google**:
1. Go to [Google Search Console](https://search.google.com/search-console)
2. Add your property (`m3hungry.com`)
3. Go to Sitemaps → submit `https://www.m3hungry.com/sitemap.xml`

Google will then crawl it on a schedule. You can see which URLs were indexed vs. had errors.

---

### 3. Meta tags in `<head>` — what Google reads per page

**File**: `apps/mehungry_web/lib/mehungry_web/views/layout/templates/head.html.heex`

This file is rendered for every page. It contains several types of tags:

#### a) `<title>`

```html
<title>Chicken Tikka Masala — Instructions and Nutrition Facts | M3Hungry</title>
```

The title is the **most important on-page SEO element**. It appears as the blue clickable link in Google results. Rules:
- Keep it under 60 characters (longer titles get cut off)
- Include the main keyword
- Include your brand name at the end

**In this codebase**, title comes from the LiveView `page_title` assign. If it's a map (recipe page), we use `title.title`. If it's a string, we append `" | M3Hungry"`. If nothing is set, we use the default.

#### b) `<meta name="description">`

```html
<meta name="description" content="Chicken Tikka Masala recipe — 4 servings, ready in 45 min. Full nutrition facts on M3Hungry." />
```

This is the text shown below the title in search results (the grey snippet). Google sometimes ignores it and picks its own text, but setting it correctly improves click-through rate.

**In this codebase**, description comes from the `page_description` assign set in each LiveView's `apply_action`. For recipe pages, it's built from the recipe's own `description` field plus cooking time and servings.

#### c) `<link rel="canonical">`

```html
<link rel="canonical" href="https://www.m3hungry.com/browse/42" />
```

This tells Google "this is the authoritative URL for this content." It prevents duplicate content issues — for example if the same page is reachable at `/browse/42` AND `/show_recipe/42`, the canonical tells Google which one to index.

#### d) `<meta name="robots">`

```html
<!-- On private pages: -->
<meta name="robots" content="noindex, nofollow" />

<!-- On public pages: -->
<meta name="robots" content="index, follow" />
```

`noindex` prevents the page from appearing in search results. `nofollow` tells Google not to follow any links on that page. This is set automatically based on the URL prefix — any URL starting with `/profile`, `/basket`, `/calendar`, `/create_recipe`, `/users/`, `/upgrade`, or `/professional/` gets `noindex, nofollow`.

#### e) Open Graph tags

```html
<meta property="og:title" content="Chicken Tikka Masala | M3Hungry" />
<meta property="og:description" content="..." />
<meta property="og:image" content="https://..." />
<meta property="og:type" content="article" />
```

Open Graph tags control how your pages appear when shared on Facebook, LinkedIn, Slack, WhatsApp, and iMessage. When someone pastes a link, these tags produce the preview card (image + title + description).

`og:type` is `"article"` for recipe pages (has an image) and `"website"` for general pages.

#### f) Twitter Card tags

```html
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:title" content="..." />
<meta name="twitter:image" content="..." />
```

Same idea as Open Graph but specifically for Twitter/X previews.

---

### 4. JSON-LD structured data — Recipe rich results

**Where it's generated**: `recipe_browser_live/index.ex` — `build_recipe_jsonld/1`

**Where it's rendered**: `head.html.heex` — injected when `@recipe_jsonld` assign is set

```html
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "Recipe",
  "name": "Chicken Tikka Masala",
  "url": "https://www.m3hungry.com/browse/42",
  "image": "https://...",
  "description": "...",
  "author": { "@type": "Person", "name": "Nikos" },
  "cookTime": "PT45M",
  "prepTime": "PT15M",
  "totalTime": "PT60M",
  "datePublished": "2026-03-15T10:00:00",
  "recipeYield": "4 servings",
  "recipeCuisine": "Indian",
  "recipeIngredient": [
    "2 cup Basmati Rice",
    "500 g Chicken Breast",
    "1 tbsp Garam Masala"
  ],
  "keywords": "curry, indian, dinner",
  "nutrition": {
    "@type": "NutritionInformation",
    "servingSize": "1 serving",
    "calories": "620 kcal",
    "proteinContent": "38.0 g",
    "fatContent": "22.0 g",
    "carbohydrateContent": "70.0 g"
  },
  "recipeInstructions": [
    { "@type": "HowToStep", "name": "Marinate", "text": "Marinate the chicken overnight..." },
    { "@type": "HowToStep", "name": "Cook", "text": "Cook on medium heat for 20 minutes..." }
  ]
}
</script>
```

**Which fields are emitted, and where the data comes from** (all built in `build_recipe_jsonld/1` and its `jsonld_*` helpers):

| JSON-LD field | Source | Notes |
|---|---|---|
| `name` | `recipe.title` | |
| `url` | `/browse/:id` | |
| `image` | `recipe.image_url` | omitted if absent |
| `description` | `recipe.description` | falls back to title |
| `author` | `recipe.author`, else `recipe.user.name` | `jsonld_author/1`; omitted if both blank |
| `cookTime` / `prepTime` | `cooking_time_lower_limit` / `preperation_time_lower_limit` | ISO-8601 `PTnM` |
| `recipeYield` | `recipe.servings` | |
| `recipeCuisine` | `recipe.cousine` | **note the misspelled schema column** |
| `recipeIngredient` | `recipe.recipe_ingredients` | `jsonld_ingredient_line/1` → `"<qty> <unit> <name>"` using `RecipeIngredient.unit_label/1` + `Utils.remove_parenthesis/1`; whole-number floats print without `.0` |
| `keywords` | `recipe.recipe_hashtags` → `hashtag.title` | comma-joined; **requires the `[recipe_hashtags: :hashtag]` preload in `Food.Recipes.get_recipe!/1`** |
| `totalTime` | `preperation_time_lower_limit` + `cooking_time_lower_limit` | `total_time_minutes/1`; omitted when both are 0 |
| `datePublished` | `recipe.inserted_at` | ISO-8601; helps freshness |
| `nutrition` | `recipe.nutrients` → `NutrientUtils.macro_summary/1` | `jsonld_nutrition/1`; `NutritionInformation` **per serving** (whole-recipe totals ÷ `servings`): `calories` + protein/fat/saturatedFat/carbohydrate/sugar/fiber/sodium. Reuses the same `macro_summary/1` the calendar/share cards use (parity rule). Omitted when there's no energy value — we never publish fabricated numbers |
| `recipeInstructions[].text` | `step.description` (or `title`) | |
| `recipeInstructions[].name` | `step.title`, else `"Step N"` | **always present now** — falls back to the 1-based position so Google never reports a missing step `name` |

**Google Search Console "Enhance item appearance" warnings** — these are the non-critical warnings ("Βελτίωση εμφάνισης στοιχείων" in the Greek console) that recipes are *valid* but could be enriched. The table above closes: `author`, `recipeIngredient`, `recipeCuisine`, `keywords`, `totalTime`, `datePublished`, **`nutrition`** (added 2026-10-19 — the app's whole reason to exist, so the biggest win), and per-step `name`. The following warnings are **deliberately left open** because the data doesn't exist and faking it violates Google's policy or misrepresents the page:

- **`aggregateRating`** — there is no recipe rating/review feature yet (`MealPlanRating` is the nutritionist meal-plan feature, unrelated). Never emit fabricated or constant ratings — it risks a manual action. Add this only once real user ratings are collected and *displayed on the page*.
- **`video`** and per-step **`image`/`video`** — no recipe video content exists (`Step` is an embedded schema with only `title`/`description`/`index` — no image field).
- **`recipeCategory`** — no dedicated meal-type field on the recipe; would have to be derived (e.g. from hashtags) and is low value, so it's skipped for now.

**What it does**: JSON-LD is a machine-readable description of your page's content using a standard vocabulary ([schema.org](https://schema.org)). Google uses it to show **rich results** — enhanced search listings that look like this:

```
Chicken Tikka Masala — M3Hungry
★★★★☆  45 min  |  4 servings
Marinate the chicken overnight, then cook on medium heat...
```

These rich results get far higher click-through rates than plain blue links.

**Format notes**:
- `PT45M` means "45 minutes" in ISO 8601 duration format (P = period, T = time, M = minutes)
- All fields are optional — Google will show rich results as long as at minimum `name`, `image`, and at least one instruction are present

**To test your JSON-LD**: Use Google's [Rich Results Test](https://search.google.com/test/rich-results) — paste a recipe URL and it will show you what Google sees and whether the structured data is valid.

---

### 5. Per-page titles and descriptions in LiveViews

**Files changed**: `apps/mehungry_web/lib/mehungry_web/live/recipe_browser_live/index.ex`

Every `apply_action` clause now sets two assigns:

```elixir
|> assign(:page_title, "\"pasta\" Recipes | M3Hungry")
|> assign(:page_description, "Search results for 'pasta' — browse recipes with USDA nutrition analysis...")
```

These flow through to `head.html.heex` via `@conn.assigns`.

**The flow**:
```
Browser requests /search/pasta
  → Phoenix router matches RecipeBrowserLive.Index
    → handle_params calls apply_action
      → apply_action assigns :page_title and :page_description to socket
        → Phoenix renders root.html.heex
          → head.html.heex reads @conn.assigns[:page_title]
            → <title> and <meta name="description"> are set
```

**To add SEO to a new page**: In that LiveView's `mount` or `handle_params`, add:
```elixir
|> assign(:page_title, "Your Page Title")
|> assign(:page_description, "A 140-character description of what this page contains.")
```

---

## Monitoring SEO

> ⚠️ **There is no longer an in-app SEO dashboard.** The old `/professional/seo`
> page (`seo_live.ex`) and the `presence.ex` referrer-capture it read from were
> **removed** together with the rest of the GA4-duplicating server-side analytics
> (the `visits` table and its dashboards — see `docs/app_status.md` and the
> *Analytics removal* memory). Don't go looking for them. SEO is now monitored
> entirely with the two tools built for it:

### 1. Google Search Console (the source of truth for organic)

This is where you see what no referrer log can tell you: **impressions, clicks,
average position, CTR, and the actual search queries** (queries are visible in
GSC even though they're stripped from the HTTP `Referer` — Google only exposes
them here).

- Add/verify the `m3hungry.com` property, then **Sitemaps → submit
  `https://www.m3hungry.com/sitemap.xml`** (see §2 above).
- Watch **Performance** for impressions/clicks per query and per page, and
  **Pages** (Index coverage) for what's indexed vs. excluded and why.
- The leading indicator worth checking weekly is **impressions on the `/foods`,
  `/conditions`, and recipe pages** — the first sign organic is starting
  (currently zero; this is the #1 compounding unlock per `docs/growth_plan.md`).
- Use the **URL Inspection** tool + **Rich Results Test** to confirm a specific
  page's indexed HTML and JSON-LD are what you expect (the dead-render gotcha in
  "How Phoenix LiveView interacts with SEO" above makes this worth doing for any
  new public LiveView).

> ✅ **We can work with Search Console programmatically — the REST API is already
> configured.** The same Google service account used for GA4
> (`GA4_SA_KEY` + `GSC_SITE_URL="sc-domain:m3hungry.com"`, see `docs/app_status.md §7`)
> is granted on the GSC property, so you don't have to click through the UI. Two
> endpoints are wired/available:
> - **Search Analytics** — `Mehungry.Report.SearchConsole.fetch/1` pulls
>   clicks/impressions/CTR/position + the `/foods` subset + top queries/pages, and
>   feeds the automated `mix report.snapshot`. Extend it for any dimension the API
>   supports (device, country, date-trend, page/query filters) — that's exactly how
>   the 2026-10-19 snapshot above was produced.
> - **URL Inspection API** (`https://searchconsole.googleapis.com/v1/urlInspection/index:inspect`,
>   same `webmasters.readonly` token from `Mehungry.Report.GoogleAuth`) returns
>   Google's per-URL **index verdict, coverage state, canonical choice, and
>   rich-result issues** — the source of the duplicate-canonical and Recipe
>   structured-data findings above. Call it ad-hoc to check any URL after a deploy +
>   recrawl without opening the console.

### 2. GA4 (organic as a traffic channel)

GA4 → **Acquisition → Traffic acquisition** breaks sessions down by channel
(Direct / Organic Search / Organic Social / Referral), so you can see organic
search as a share of total traffic. Note GA4 is **consent-gated** (it only counts
visitors who accepted the cookie banner) and is **not queryable from the
codebase** — pull it by hand from the GA4 UI. See `docs/app_status.md §5.3`.

---

## How Phoenix LiveView interacts with SEO

Phoenix LiveView is unusual from an SEO perspective because it has two rendering modes:

1. **Initial HTTP request**: When Googlebot (or a browser) first visits a page, Phoenix renders the full HTML on the server and sends it. This is called **Server-Side Rendering (SSR)**. The content is fully visible in the HTML source.

2. **Subsequent navigation**: After the page loads, the browser opens a WebSocket connection to the server. Further navigation updates happen over that WebSocket — the URL changes but no full HTML is sent. Googlebot doesn't follow WebSocket updates.

**This means**: For SEO purposes, only the initial HTTP render matters. When Googlebot visits `/browse/42`, it gets a fully rendered recipe page. When it visits `/browse` and the user clicks a recipe, Googlebot never sees that click — but it already indexed `/browse/42` separately via the sitemap.

**The `page_title` assign quirk**: Setting `assign(socket, :page_title, "...")` in LiveView changes the `<title>` tag for a new browser session, but after the WebSocket connects, subsequent `handle_params` calls that change `page_title` are **not reflected in the `<head>`** — the head was already sent. This is fine for SEO (each URL is requested fresh by Googlebot), but means the browser tab title doesn't update on client-side navigation without extra JavaScript.

**⚠️ Critical: `assign_async` content is invisible to crawlers.** Because only the disconnected HTTP render is indexed, **any content loaded via `assign_async` (or `start_async` / `handle_async`) is *not* in the HTML Googlebot sees** — on the dead render those assigns are still in their `loading` state, so the template renders loading skeletons, and the real data only arrives after the WebSocket connects (which crawlers don't do). If the substantive, rankable content of a public page is behind `assign_async`, that page effectively looks empty to Google.

The pattern to keep a page both snappy *and* indexable is to branch on `connected?/1` in `mount` — async for the live client, synchronous for the crawler — handing the template a resolved `Phoenix.LiveView.AsyncResult` so the render code is identical either way:

```elixir
defp load_data(socket, id) do
  if connected?(socket) do
    assign_async(socket, [:thing], fn -> {:ok, %{thing: expensive_load(id)}} end)
  else
    # dead render → real HTML for Googlebot
    assign(socket, :thing, Phoenix.LiveView.AsyncResult.ok(expensive_load(id)))
  end
end
```

This is exactly the fix applied to both condition pages and the species detail page (below). **Audit any new public `assign_async` LiveView the same way** — if the async assign holds rankable content or internal links, it needs the `connected?/1` split.

---

## Food pages (`/foods/:slug`)

**`/foods/:slug` is served by `SpeciesDetailLive.Index`** — a *species* page (e.g. `/foods/Agave`), resolved via `Food.get_species_by_slug/1` (species name with spaces → hyphens). It shows the nutrition of the species' connected USDA ingredients, with a `<select>` dropdown (`select_ingredient` event) to switch which ingredient's breakdown is displayed.

> ⚠️ `FoodDetailLive.Index` (a per-*ingredient* page) exists in the tree but is **not routed** — it is dead code, superseded by `SpeciesDetailLive`. Don't extend it; edit the species page.

SEO on the species page:

- **`page_title` / `page_description`**: plain strings, language-aware (English or Greek depending on `current_language`). Title is `"<name> — Nutrition, Research & Compounds"`.
- **No `page_seo_data` map**: the map form in `head.html.heex` hardcodes canonical as `/browse/<id>` (recipe-specific), and species have no image for an OG slot — so food pages use the plain-string `page_title` path. Canonical resolves correctly via `@conn.request_path`.
- **Canonical + hreflang are handled generically.** The app now has locale-prefixed routes (`/en/...`, `/el/...`), and `head.html.heex` emits a locale-aware canonical (`Locale.swap_path/2`) plus one `<link rel="alternate" hreflang>` per supported locale (+ `x-default`) for **any** page where `@locale` is assigned — food pages qualify via the `:browser`/`RestoreLocale` pipeline, so no per-page work is needed. *(This supersedes the old "hreflang not implemented" note.)*
- **JSON-LD** (`:structured_data`, `build_structured_data/6` → `@graph`, rendered by `head.html.heex`): a `BreadcrumbList` (Foods › name — the real rich-result win) + a `WebPage` whose `MenuItem` `mainEntity` carries a `NutritionInformation`. The nutrition node reflects the **default-selected ingredient's** tree (the one painted on first load; switching ingredients happens over the socket, after the head is sent). **Only macro / level-1 fields** map, because `NutritionInformation` has no schema.org fields for individual sugars or fatty acids: `calories`, `proteinContent`, `fatContent`/`saturatedFatContent`/`transFatContent`/`unsaturatedFatContent`, `carbohydrateContent`/`sugarContent`/`fiberContent`, `sodiumContent`, `cholesterolContent`, `servingSize: "100 g"` (units normalized to `kcal`/`g`/`mg`/`µg`). We deliberately do **not** emit `schema.org/Recipe` for a food (no ingredients/instructions — Google would flag it as misleading). The deep sugar/fatty-acid breakdown's SEO value comes from the crawlable visible text, not the JSON-LD.
- Food pages **are** in `sitemap.xml` (publicly indexable, not in the `noindex` prefix list).

**The full breakdown is the shared hierarchical accordion.** The "Full Nutrition Breakdown — per 100g" section renders the string-keyed, nested per-100g tree (`Food.NutrientCalculation.ingredient_nutrient_tree(ingredient, 100)`) through `MehungryWeb.NutritionAccordion` — the *same* component the calendar/recipe "Nutrition Facts" uses, so the presentation is identical. Carbohydrates → Total Sugars → individual sugars (glucose/fructose) and Total Fat → saturated/mono/poly/trans → fatty acids are all present. The accordion's collapsed children are **`display:none` but in the DOM**, so every sugar/fatty-acid leaf is crawler-visible once the tree is server-rendered (see below). A short, deterministic **composition summary** `<p>` above the accordion (`build_composition_summary/2`, e.g. *"Per 100 g, … provides … g carbohydrate … almost entirely sugars, led by fructose and glucose"*) is the highest-value indexable prose, carrying the long-tail nutrient terms with one line of clutter.

**`assign_async` audit:** the page's *core* content — the nutrition facts (top macros + the full accordion breakdown + composition summary) — is rendered **synchronously** in `mount` via `assign_ingredient_view/2`, so it is crawler-visible in the dead render (the main SEO asset for "food X nutrition/calories/sugar" queries was never at risk). Three **secondary** sections — "Bioactive Compounds", "Health Conditions", "Research" — were loaded via `assign_async` and were invisible to Googlebot: the title advertised "Nutrition, Research & Compounds" while the indexed HTML had only nutrition, and the "Health Conditions" section's **internal links to `/conditions/:id`** (which help that cluster rank) weren't in the crawled markup. Fixed with the `connected?/1` split (`load_species_sidecars/2`): async for the live client, synchronous `AsyncResult.ok(...)` on the dead render.

---

## Condition pages (`/conditions/:id`)

> 🚫 **DEPRECATED / BEING REMOVED (2026-10-19) — condition pages are no longer part of the
> project.** Surfacing dietary advice targeted at named medical conditions ("foods to eat /
> avoid for ulcerative colitis", etc.) makes the product a **regulated medical device** under
> EU MDR / software-as-a-medical-device rules — a compliance burden we **cannot support for
> now**. The `/conditions/:id` pages, their SEO targeting, and any condition-query growth plan
> are therefore **off the roadmap**. Do **not** invest further in ranking them, and do not treat
> condition queries as an opportunity elsewhere in this doc (the 2026-10-19 snapshot section
> flagged them before this decision — that guidance is now void). The content below is retained
> only as historical record of what the pages did while they existed.

`ConditionDetailLive.Index` (e.g. `/en/conditions/16` = Peptic Ulcer Disease) is a high-value SEO target: it matches informational health queries like "peptic ulcer diet", "foods to avoid", "what to eat when you have ulcers". Search Console showed it *ranking* for exactly those queries but at **position ~80** (page 8) with **0 clicks** — indexed and topically relevant, but far too low to earn traffic. Diagnosis and the fixes applied:

### Fixed

1. **Async content was hidden from Googlebot.** The recommendations and food species — the entire substance of the page — were loaded via `assign_async` in `mount`, so the crawler-indexed dead render showed only loading skeletons (see the `assign_async` caveat under "How Phoenix LiveView interacts with SEO" above). `mount` now branches on `connected?/1` via `load_condition_data/2`: async for the live client, synchronous `AsyncResult.ok(...)` for the dead render, so the crawler gets the real foods and compounds. **This was the dominant cause of the position-80 ranking** — the page looked nearly empty to Google.

2. **Vocabulary alignment.** Title/description/headings spoke in scientific register; searchers don't. Changes:
   - **Title** (`seo_title/1`): `"<condition> Diet: Foods to Eat & Avoid"` — leads with "diet"/"foods to eat"/"foods to avoid" (the actual queries) instead of "— Dietary Guidance".
   - **Description** (`seo_description/1`): leads with "diet guide … foods to eat … foods to avoid", and appends the condition's `synonyms` ("Also called …") to catch synonym queries (stomach ulcer, gastric ulcer, …).
   - **Section headings**: "Foods to Be Mindful Of" → **"Foods to Avoid or Limit"**; "Encouraged Foods" → **"Foods to Eat"**.
   - **Synonyms** are now also rendered as visible body text under the `<h1>` (they were stored on `Health.Condition.synonyms` but never surfaced).

### Still open (deliberately not done here — these are content/editorial work, not code)

3. **YMYL depth + E-E-A-T is the real ranking ceiling.** Diet-for-a-medical-condition is "Your Money or Your Life" content, which Google holds to its highest quality bar and where it strongly favors authoritative sources (Mayo Clinic, Healthline). Even with #1 and #2, a compound/species data table will struggle against long-form articles because the page lacks: (a) editorial prose explaining *why* each food is recommended (the "is peanut butter good for ulcers?" intent needs a sentence, not a badge); (b) **visible citations** — the literature provenance already exists in the data model (`Literature.*`, `SpeciesCompoundRelationship` studies) and should be surfaced on the page; (c) an **author / medical reviewer** byline and a "last updated" date. This is the durable, multi-month play.

4. **Per-recommendation rationale.** Add a short "why" to each recommendation row so the page answers the question-shaped queries ("is X good for ulcers", "popcorn and ulcers") directly.

5. **Structured data.** Once real prose exists, add JSON-LD — `MedicalWebPage`, and/or `FAQPage` for the question-shaped queries. Don't add it before the content exists (Google flags structured data that doesn't match visible content).

**Re-measure after deploy + recrawl (~2–4 weeks):** expect #1 to move position materially on its own (the crawler can finally see the page); wording tweaks (#2) compound on top. #3–5 are what move it from page 8 to page 2–3.

## Meal plan pages (`/meal-plans/:slug`)

`MehungryWeb.MealPlanLive.Show` is the **SEO + sharing surface for meal planning**.
The personal calendar (`/calendar`) is private, `noindex`, Disallowed in
`robots.txt`, and WebSocket-driven — it can never rank. So instead a user
**publishes a chosen week** as an immutable public snapshot
(`Mehungry.PublishedPlans` → `published_meal_plans`) served at a crawlable
`/meal-plans/:slug`. This targets the high-volume "7-day meal plan" / "weekly
meal plan" / "μεσογειακό εβδομαδιαίο πρόγραμμα" query space with content no
recipe-blog listicle can match on nutrition accuracy.

- **`PublishedPlans.publish_week(user, week_start, opts)` is self-contained** — it
  re-derives the week from the DB (`History.list_calendar_user_meals/3` +
  `History.format_user_meals/1`), so no LiveView socket state is needed. Macro
  numbers come from the **same** `NutrientUtils.summarize_meals_nutrients/1` +
  `macro_summary/1` the calendar uses (parity rule), so the page matches the
  calendar to the gram. The snapshot (days + macros + grocery + prose) is stored
  immutably, so the public URL never churns when the author edits their calendar
  and leaks no live PII.
- **Rendered synchronously** (no `assign_async`) — the dead render Googlebot
  indexes already carries the full 7-day plan, so there is no `connected?/1` split
  to maintain (see the `assign_async` caveat above). Each recipe row is an
  `<a href="/browse/:id">` — the internal-linking unlock (§"What to do next" #4),
  35 links per plan into the recipe cluster.
- **SEO assigns**: plain-string `:page_title` (= plan title) + `:page_description`
  (the prose summary) + `:canonical_path` (`/meal-plans/:slug`, locale swapped in
  generically) + `:og_image` (reuses the generated weekly **share card** when the
  publish flow passes one). `:og_image` is a new **generic** override in
  `head.html.heex` (mirrors the existing `:canonical_path` override) so any
  plain-string page can set a custom OG image without the recipe `page_seo_data`
  map (which hardcodes a `/browse/:id` canonical).
- **JSON-LD** (`:structured_data`): a `BreadcrumbList` (Home › Meal Plans › title)
  + an `ItemList` of the plan's recipes (each `url` → `/browse/:id`). There is **no
  schema.org `MealPlan` type and no meal-plan rich result** — the win is ranking +
  CTR + internal links, not a SERP card. We deliberately do **not** fabricate
  `aggregateRating` (same policy trap as recipes).
- **Sitemap + robots**: public plans are emitted in `sitemap.xml`
  (`PublishedPlans.list_public_plans/0`, localized entries) and `/meal-plans` is
  `Allow`ed in `robots.txt`. `/meal-plans` is **not** in `head.html.heex`'s
  `noindex_prefixes`.

**Publish trigger + feed integration.** Publishing is wired to the calendar's
weekly share flow: when a user posts their week to the feed
(`calendar_live/index.ex` `post_week_plan`), it calls `publish_week/3` (passing
the generated share card as `:og_image_url`) and links the resulting
`WEEKLY_PLAN` feed post to the plan via `posts.published_meal_plan_id`. The feed
card (`home_live/components/post_card.html.heex`) then opens
`/meal-plans/:slug` — the full day-by-day details page — instead of the raw card
image, and the details page shows a **"Shared by &lt;name&gt;"** byline linking to
the author's `/profile/:id`. Older posts with no linked plan fall back to the
image.

**One plan + one post per `(user, week_start)`.** Re-posting a week the user has
already published **replaces** rather than duplicates: `publish_week/3` upserts
the `PublishedMealPlan` in place (keeping the same `slug`, so the public URL and
shared links stay stable while the snapshot refreshes), and
`create_weekly_plan_post/3` deletes the prior `WEEKLY_PLAN` post for that plan
before inserting the fresh one — so the feed never shows two cards for the same
dates. Publishing a *different* week makes a separate plan as expected.

**Card image + one-click "Add to my calendar".** The details page shows the
generated PNG share card (`og_image_url`) as a hero image, and the snapshot
stores each item's FK ids (recipe / ingredient / unit) so a logged-in visitor
can **re-create the whole week on their own calendar** with one button
(`use_plan` → `PublishedPlans.import_to_calendar/3`, laying day-index 0..6 onto
the Monday of the current week, non-destructively; mirrors
`MealBlueprints.import_plan_to_calendar/3`). Anonymous visitors get a log-in CTA.
Free-food slots (and any pre-FK-snapshot plans) are shown but skipped on import.

## Checklist: verifying the implementation

After deploying, confirm these work:

- [ ] `https://www.m3hungry.com/robots.txt` — opens and shows the disallow rules
- [ ] `https://www.m3hungry.com/sitemap.xml` — opens and lists recipe, hashtag, and food (`/foods/:slug`) URLs
- [ ] View source of a recipe page (`/browse/42`) — check `<title>`, `<meta name="description">`, and `<script type="application/ld+json">` are present
- [ ] View source of `/profile` — check `<meta name="robots" content="noindex, nofollow">` is present
- [ ] Google's [Rich Results Test](https://search.google.com/test/rich-results) with a recipe URL — confirms JSON-LD is valid
- [ ] Submit sitemap to [Google Search Console](https://search.google.com/search-console)

---

## SEO snapshot — 2026-10-19 (GSC + URL Inspection + Lighthouse)

First deep read using the automated Search Console pull (`Mehungry.Report.SearchConsole`,
see `docs/app_status.md §7`) plus the GSC **URL Inspection API** and a **Lighthouse**
snapshot audit. Re-run roughly monthly.

### Trajectory — organic has started and is improving
28-day window vs the prior 28 days (domain property `sc-domain:m3hungry.com`):

| Metric | Prior 28d | Last 28d |
|---|---|---|
| Clicks | 7 | **13** |
| Impressions | 1,824 | 828 |
| CTR | 0.38% | **1.57%** |
| Avg position | **50.1** | **12.6** |

The impression *drop* is healthy: the prior period was mostly junk impressions stuck at
position ~50 (page 5, invisible). Clicks ~2×, CTR ~4×, and average position moved from
page 5 to page 1–2 — Google has promoted the useful pages. Desktop 608 impr / mobile 220;
mobile ranks better (pos 9.6 vs 13.7).

### Two query clusters
1. **USDA-nutrient noise** (high impressions, ~0 clicks): `"beef, ribeye, steak… calories"`,
   `"bananas, overripe, raw" "sucrose"`, `abiyuch`, `cabbage nutrition information`. These are
   `/foods` pages matching literal USDA food-description strings — they rank well (pos 6–8) but
   are not human queries. This is why **USA = 308 impressions but CTR 0.65%**.
2. **Health-condition queries — ⚠️ NOT pursued (see below).** The data showed high-intent
   queries (`best foods for ulcerative colitis`, `colitis diet`, `colitis foods to avoid list`,
   Hungarian `colitis étrend`) ranking at position 69–85, which *looked* like the biggest
   opportunity. **As of 2026-10-19 this is off the roadmap:** condition pages are being removed
   because condition-targeted dietary advice makes the app a regulated medical device (see the
   🚫 notice under "Condition pages" below). Do not invest in ranking these.

### Google's URL-Inspection verdicts
Indexing is healthy — `/en/welcome`, `/en/browse`, `/en/conditions/13`, `/en/browse/180` all
**PASS / "Submitted and indexed"**, robots ALLOWED, fetch SUCCESSFUL. Two issues:

1. **Recipe structured-data warnings — FIXED 2026-10-19.** On recipe `/en/browse/180` Google
   flagged the Recipe JSON-LD missing `nutrition`, `recipeCategory`, `aggregateRating`,
   `recipeCuisine`, `totalTime`, and per-step `name`/`image`. Closed the data-backed ones in
   `build_recipe_jsonld/1`: added `nutrition` (per-serving `NutritionInformation` from
   `recipe.nutrients`), `totalTime`, `datePublished`, and a `"Step N"` fallback so every
   `HowToStep` is named. `aggregateRating` / `video` / step-images / `recipeCategory` remain
   open **by design** (no real data — see the warnings list in §4). Re-verify with the
   [Rich Results Test](https://search.google.com/test/rich-results) after deploy + recrawl.
2. **Greek `/foods` pages lose to duplicate-canonical (open).** `/en/foods/Κάρδαμο` returns
   **NEUTRAL — "Duplicate, Google chose different canonical than user"**: Google picked
   `/en/foods/Cress` as canonical. The Greek-named food URLs aren't indexed on their own —
   they're folded into the English equivalent. Decide whether Greek food pages should carry
   distinct localized content/canonical or deliberately point at the English page (and set the
   canonical accordingly). Until then, Greek food-term queries can't rank their own URL.

### Lighthouse (mobile, snapshot mode)
`https://www.m3hungry.com/en/browse/180` — **SEO 100 / Best Practices 100** (titles, meta,
crawlable links, hreflang, valid structured data all pass), **Accessibility 84**. Note:
`navigation` mode returns `NO_FCP` on LiveView pages in headless Chrome — use `mode: "snapshot"`
against an already-loaded page. Accessibility failures (not direct ranking factors, but worth
fixing for page experience + real users):

- **color-contrast** — hashtag chips (`#greek`, `#cretan`, …) render white on `#fb923c`
  (`bg-primary-400`) = **2.26:1** (need 4.5:1); the **cookie-consent "Accept" button** is
  `#333` on `#101729` = **1.41:1** (appears on every page). Darken the chip background
  (`primary-500/600`) and fix the consent-button colors.
- **button-name** — the mobile search submit button (`#recipe-search-form button.absolute`) has
  no accessible name (icon-only). Add `aria-label`.
- **link-name** — the login-overlay link (`a[href="/users/log_in"]` on the recipe image) has no
  discernible text. Add `aria-label`.
- **aria-dialog-name** — `#recipe_details_modal` `role="dialog"` has no accessible name
  (`aria-labelledby` points at an element that isn't present on the dead render).
- **label-content-name-mismatch** — the modal's "Back" button has `aria-label="close"` while its
  visible text is "Back"; make the accessible name contain the visible text.

---

## What to do next

These items would have the biggest remaining impact:

1. ~~**Create a default OG image** at `/images/og-default.png` (1200×630px).~~
   **Done** — a brand-lockup card (parchment ground, logo mark, "m3hungry"
   wordmark, tagline) lives at `apps/mehungry_web/priv/static/images/og-default.png`,
   with its editable source alongside it as `og-default.svg`. It's the fallback
   `og:image`/`twitter:image` for every page without a recipe image (home,
   `/foods`, `/conditions`, `/blueprints/:slug`, `/nutritionists`). To re-render
   after editing the SVG: `vips copy og-default.svg og-default.png` (libvips uses
   librsvg, which renders fonts correctly — ImageMagick's built-in SVG renderer
   does **not**, so don't use `convert` for this).

2. **Google Search Console** — set it up, verify ownership, submit the sitemap. This gives you actual impressions, clicks, average position, and CTR data. See "Monitoring SEO" above — GSC is now the source of truth for organic (there is no in-app SEO dashboard anymore).

3. **Recipe review schema** — the remaining big JSON-LD gap is `aggregateRating` (see the Search Console warnings table above; the cheaper `author`/`recipeIngredient`/`recipeCuisine`/`keywords`/step-`name` enhancements are already emitted). If you add a rating/review feature, adding `aggregateRating` will show star ratings in Google results, which dramatically increases click-through rate — but only mark up ratings you actually collect and display on the page.

4. **Internal linking** — make sure recipe pages link to related hashtag pages, and hashtag pages link to individual recipes. This helps Googlebot discover more content by following links rather than relying solely on the sitemap.

5. **Page speed** — Google's Core Web Vitals (loading speed, interactivity, layout stability) are a ranking factor. Use [PageSpeed Insights](https://pagespeed.web.dev) to check your scores.

---

## Worked example: nutritionist profiles (local SEO)

`/nutritionists` (directory) and `/nutritionists/:slug` (profile) are public, localized pages
built for **local intent** ("nutritionist Rethymno"). They follow the rules above:

- Plain-string `:page_title` + `:page_description` + explicit `:canonical_path` (the request
  path — the recipe `page_seo_data` map is *not* used because it hardcodes `/browse/:id`).
- The profile body is loaded **synchronously** in `mount` (no `assign_async`), so the dead
  render Googlebot indexes carries the real bio/city.
- `:structured_data` emits **`LocalBusiness` + `Person`** JSON-LD (address / `areaServed` =
  city, telephone, specialty) — the signal that drives local ranking. The directory emits
  `ItemList`.
- Sitemap includes `/nutritionists` + one localized entry per published profile; `robots.txt`
  allows `/nutritionists` and disallows the private `/nutritionist/` workspace. **Do not** add
  the singular `/nutritionist` to `noindex_prefixes` in `head.html.heex` — it would also match
  the public plural `/nutritionists`.

See `docs/professionals/professional_profiles.md`.
