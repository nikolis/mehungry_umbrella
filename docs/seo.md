# SEO Guide for M3Hungry

This document explains what SEO is, why it matters, and exactly how it works in this codebase — so you can understand, extend, and monitor it without needing prior SEO experience.

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
  "recipeYield": "4 servings",
  "recipeCuisine": "Indian",
  "recipeIngredient": [
    "2 cup Basmati Rice",
    "500 g Chicken Breast",
    "1 tbsp Garam Masala"
  ],
  "keywords": "curry, indian, dinner",
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
| `recipeInstructions[].text` | `step.description` (or `title`) | |
| `recipeInstructions[].name` | `step.title` | per-step enhancement; omitted if step has no title |

**Google Search Console "Enhance item appearance" warnings** — these are the non-critical warnings ("Βελτίωση εμφάνισης στοιχείων" in the Greek console) that recipes are *valid* but could be enriched. The table above closes: `author`, `recipeIngredient`, `recipeCuisine`, `keywords`, and per-step `name`. The following warnings are **deliberately left open** because the data doesn't exist and faking it violates Google's policy or misrepresents the page:

- **`aggregateRating`** — there is no recipe rating/review feature yet (`MealPlanRating` is the nutritionist meal-plan feature, unrelated). Never emit fabricated or constant ratings — it risks a manual action. Add this only once real user ratings are collected and *displayed on the page*.
- **`video`** and per-step **`image`/`video`** — no recipe video content exists.
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

## Monitoring SEO in the admin panel

The `/professional/seo` dashboard (built in `seo_live.ex`) shows:

| Section | What it tells you |
|---------|-------------------|
| **Organic traffic trend** | How many visitors are arriving from search engines per day |
| **Search engine breakdown** | Which search engines (Google, Bing, DuckDuckGo) send traffic |
| **Organic landing pages** | Which of your pages rank in search results |
| **Crawler activity** | When Googlebot last crawled your site and which pages it visited |
| **Search queries detected** | What search terms people used (rarely available due to Google's HTTPS privacy policy) |

**Important caveat**: The SEO dashboard only shows data for visits that happened **after** the referrer capture was added to `presence.ex`. Older visit records have no `referrer` field and will all appear as "direct." The data will build up over time.

**The referrer capture works like this**:
1. When a visitor arrives from Google and opens a page, their browser sends an HTTP `Referer` header with the Google URL
2. Phoenix LiveView receives this via `get_connect_params(socket)["_live_referer"]` during the WebSocket handshake
3. It's stored in the `visits` table as `details["referrer"]`
4. The SEO dashboard classifies it as "search" if the domain matches a known search engine

**Why we can't see Google's search queries**:
In the early days of the web, Google's referrer URL looked like `https://www.google.com/search?q=chicken+recipe`, so websites could see what people searched. In 2011, Google switched to HTTPS and stopped including the query parameter. Now you get `https://www.google.com/` as the referrer — you know traffic came from Google, but not the search term. The only way to see actual queries is via Google Search Console.

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

## Food/ingredient pages (`/foods/:slug`)

`FoodDetailLive.Index` (nutrition-facts pages for individual ingredients) follows a deliberately smaller subset of the recipe-page pattern above:

- **`page_title` / `page_description`**: set as plain strings, language-aware (mirroring the page's own `display_name` logic — English or Greek depending on `current_language`).
- **No `page_seo_data` map**: the map form in `head.html.heex` hardcodes canonical resolution as `/browse/<id>`, which is recipe-specific. `Mehungry.Food.Ingredient` also has no image field to put in an OG image slot. Since there's nothing to gain (no image) and something to lose (wrong canonical unless `head.html.heex` is also made type-aware), food pages stick to the plain-string `page_title` path, which already resolves canonical correctly via `@conn.request_path`.
- **No JSON-LD**: `schema.org/Recipe` doesn't fit a raw ingredient (no ingredient list or instructions — forcing it risks Google flagging misleading structured data). `NutritionInformation` isn't a standalone schema.org type; it's only valid nested inside a `Recipe`/`Diet` node. There's no clean schema.org type for a bare nutrition-facts page, so none is emitted. Plain title/description/semantic HTML (h1/h2 + tables) is the right amount of SEO investment here.
- **hreflang**: not implemented anywhere in the app (recipe or food pages) because there are no language-specific URL paths — `current_language` is a runtime session assign, not part of the URL, so there's no second URL for `hreflang` to point at. Proper support would require a URL-structure change (e.g. `/en/...` vs `/el/...`) well beyond incremental SEO work. Revisit only if the app ever adopts language-prefixed routes.
- Food pages **are** included in `sitemap.xml` (see below) since they're publicly indexable and not in the `noindex` prefix list.

**Species detail (`/foods/:slug`, `SpeciesDetailLive.Index`) — `assign_async` audit:** unlike the condition page, this page's *core* content — the nutrition facts (top macros + full nutrient-by-family breakdown) — is rendered **synchronously** in `mount` via `assign_ingredient_view/2`, so it was always crawler-visible (the main SEO asset for "food X nutrition/calories" queries was never at risk). But three **secondary** sections — "Bioactive Compounds", "Health Conditions", and "Research" — were loaded via `assign_async` and therefore invisible to Googlebot: the page title advertised "Nutrition, Research & Compounds" while the indexed HTML had only the nutrition, and the "Health Conditions" section's **internal links to `/conditions/:id` pages** (which help that cluster rank) weren't in the crawled markup. Fixed with the same `connected?/1` split (`load_species_sidecars/2`): async for the live client, synchronous `AsyncResult.ok(...)` on the dead render.

---

## Condition pages (`/conditions/:id`)

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

## Checklist: verifying the implementation

After deploying, confirm these work:

- [ ] `https://www.m3hungry.com/robots.txt` — opens and shows the disallow rules
- [ ] `https://www.m3hungry.com/sitemap.xml` — opens and lists recipe, hashtag, and food (`/foods/:slug`) URLs
- [ ] View source of a recipe page (`/browse/42`) — check `<title>`, `<meta name="description">`, and `<script type="application/ld+json">` are present
- [ ] View source of `/profile` — check `<meta name="robots" content="noindex, nofollow">` is present
- [ ] Google's [Rich Results Test](https://search.google.com/test/rich-results) with a recipe URL — confirms JSON-LD is valid
- [ ] Submit sitemap to [Google Search Console](https://search.google.com/search-console)

---

## What to do next

These items would have the biggest remaining impact:

1. **Create a default OG image** at `/images/og-default.png` (1200×630px). This is shown when sharing pages that don't have a recipe image (browse, home, etc.).

2. **Google Search Console** — set it up, verify ownership, submit the sitemap. This gives you actual impressions, clicks, average position, and CTR data — far more accurate than the referrer-based analytics we track in the app.

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
