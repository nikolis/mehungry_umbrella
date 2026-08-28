# Professional (Nutritionist) Articles

How a nutritionist (`pro` tier) authors long-form, publicly discoverable, evidence-based
articles — where **each paragraph can carry its own image and its own scientific references** to
PubMed studies, food species, chemical compounds, and diseases. Profiles and booking are
documented separately in `professional_profiles.md` and `appointments_booking.md`.

## What this is for

Articles are public educational content, server-rendered for search-engine indexing and shown
on the author's public profile. They let a nutritionist cite the same first-class scientific
entities the rest of the app already models, turning loose prose into a referenced piece with a
numbered bibliography.

Referenced entities (all pre-existing registries — the article layer only *links* to them):

| Reference kind | Entity | Module |
|---|---|---|
| `study` | PubMed paper (keyed by `pmid`) | `Mehungry.Literature.ScientificStudy` |
| `species` | Fundamental food species (by `scientific_name`) | `Mehungry.Food.FoundementalFoodSpecies` |
| `compound` | Bioactive/chemical compound | `Mehungry.Food.Compound` |
| `condition` | Disease/health condition | `Mehungry.Health.Condition` |

## Data model (`Mehungry.Professionals`)

Three schemas under `apps/mehungry/lib/mehungry/professionals/`, owned by the flat
`Professionals` context (like appointments/invitations).

### `Article` — table `professional_articles`
- `belongs_to :professional_profile` (the author is `profile.user`)
- `title`, `slug` (unique), `summary`, `cover_image_url`
- `status` — `"draft"` | `"published"` (default `"draft"`)
- `published_at` (utc_datetime, set on first publish, kept stable afterward)
- `has_many :paragraphs` (preloaded `order_by: [asc: :position]`), `has_many :references`

**Slug behaviour.** A new article is created with a placeholder title `"Untitled article"`. Its
slug **tracks the title while the article is a draft** (`Professionals.maybe_reslug/2` → re-slugs
from the title on every draft update via `ProfessionalProfile.slugify/1`) and is **frozen once
published**, so the public URL never changes under a live article. Collisions are disambiguated
by `ensure_unique_article_slug/2` (`-1`, `-2`…), mirroring the profile-slug logic.

### `ArticleParagraph` — table `professional_article_paragraphs`
- `belongs_to :article`, `position` (integer), `heading` (optional), `body` (plain text)
- `image_url`, `image_caption` — **one optional image per paragraph**
- `has_many :references`

### `ArticleReference` — table `professional_article_references`
A **polymorphic-lite** join: `reference_type` names which one of four nullable typed FKs is set.
- `belongs_to :article` (kept for cheap article-wide bibliography aggregation) and
  `belongs_to :paragraph`
- `reference_type` ∈ `study | species | compound | condition`
- `study_id` / `species_id` / `compound_id` / `condition_id` (exactly one set)
- The changeset validates that the FK **matching** `reference_type` is present.
- A unique index (`professional_article_references_unique_target` on
  `[paragraph_id, reference_type, study_id, species_id, compound_id, condition_id]`) stops the
  same entity being cited twice from one paragraph.

All FKs are `on_delete: :delete_all` (deleting an article/paragraph, or a referenced entity,
removes the dependent reference rows).

## Context API (`professionals.ex`)

- **Articles:** `list_articles_for_profile/1`, `list_published_articles_for_profile/1`,
  `get_article/1`, `get_article!/1`, `get_published_article_by_slug/1` (published only, fully
  preloaded incl. author profile+user), `create_article/1`, `update_article/2`,
  `publish_article/1`, `unpublish_article/1`, `delete_article/1`, `change_article/2`.
- **Paragraphs:** `create_paragraph/2` (appends after the current last `position`),
  `get_paragraph!/1`, `update_paragraph/2`, `delete_paragraph/1`, `reorder_paragraphs/2` (writes
  each id's index as its `position`).
- **References:** `add_reference/2` (`paragraph`, attrs — fills `article_id`/`paragraph_id`),
  `delete_reference/1`, `get_reference!/1`, `list_references_for_paragraph/1`.

### Reference pickers — reused / added collaborators
- **Species** (large table) — `Mehungry.Food.search_species/1` **(new)**: ILIKE over `name` /
  `scientific_name` / `alternative_name`, capped (default 20). Delegated from the `Food` facade
  to `FoundementalFoods`.
- **Compounds** — `Mehungry.Food.list_compounds/0` (small registry, filtered in the LiveView).
- **Conditions** — `Mehungry.Health.list_conditions/0` (small registry).
- **PubMed** — `Mehungry.Literature.fetch_and_upsert_study/1` **(new)**: accepts an integer or
  string PMID, returns the stored `ScientificStudy` if present (no network), else fetches
  metadata via the existing Entrez `Client.efetch([pmid])` and `upsert_study/1`. Returns
  `{:error, :not_found | :invalid_pmid | reason}`. This lets an author cite **any** paper, not
  only ones the species crawl discovered.

## Authoring — nutritionist workspace

Routes in the subscription-gated `:nutritionist` live_session (`NutritionistAuthLive`):

- `/nutritionist/articles` → `MehungryWeb.NutritionistLive.Articles` — the author's list (draft +
  published) with View/Edit/Delete, and a **New article** button that creates the placeholder
  draft and navigates into the editor.
- `/nutritionist/articles/:id/edit` → `MehungryWeb.NutritionistLive.ArticleEditor`.

A sidebar link ("Articles", `hero-document-text`) sits in `nutritionist_sidebar/1`
(`layout_view.ex`).

### The editor (`ArticleEditor`)

Ownership is checked on mount (`article.professional_profile_id == profile.id`, else redirect).
The editor **persists incrementally** — paragraphs and references are their own rows, created /
removed / reordered live:

- **Header form** (`save_article`): title, summary, cover image. Publish / Unpublish buttons.
- **Paragraphs**: add / delete / reorder (↑ ↓ via `reorder_paragraphs/2`); each paragraph is its
  own form (`save_paragraph`) for heading + body.
- **Images** reuse the profile-photo pattern — `allow_upload(..., external: &presign_upload/2)`
  with `MehungryWeb.SimpleS3Upload.meta_for(entry, 5_000_000, "article_images")`. Two uploads: a
  `:cover` on the header, and a single `:paragraph_image` bound to the paragraph whose image
  drawer is open (`image_paragraph_id`) — mirroring `ProfileEdit`'s single `:photo` upload rather
  than one upload config per card.
- **References panel** per paragraph: a PMID text box, a species search box
  (`search_species` → clickable results), and compound/condition `<select>`s. Attached
  references render as removable chips; `add_study_ref` surfaces a flash if the PMID can't be
  resolved.

> **LiveView gotcha:** hidden per-paragraph id inputs are named `_id`, not `id` — LiveView
> reserves the `id` form attribute. The corresponding `handle_event/3` clauses match `"_id"`.

## Public rendering (SEO)

Route in the localized, `:maybe` live_session (alongside the profile routes):

```
/nutritionists/:slug/articles/:article_slug → MehungryWeb.PublicNutritionistLive.Article
```

- Loads via `get_published_article_by_slug/1` and asserts the article's profile slug matches the
  URL; **drafts / unknown slugs `push_navigate` back to the profile**.
- Rendered **synchronously in mount** so the disconnected ("dead") render Googlebot indexes
  carries the whole body — cover, title, author, per-paragraph headings/body/images, and the
  bibliography.
- **`Article` JSON-LD** is emitted via the shared `:structured_data` assign the head template
  reads (`head.html.heex`, same seam as the profile's `LocalBusiness`/`Person`): `headline`,
  `description`, `image`, `datePublished`/`dateModified`, `author` (Person → profile URL),
  `publisher`, and `citation` (built from the deduped paragraph references). Plus `page_title`,
  `page_description`, `canonical_path`.
- **Numbered bibliography.** `numbered_references/1` flattens all paragraph references in
  encounter order, dedupes by `{reference_type, *_id}`, and assigns each a number shared by the
  inline superscript markers and the foot "References" list. PubMed refs link out to
  `https://pubmed.ncbi.nlm.nih.gov/<pmid>` (`rel="noopener nofollow"`).

Two more public surfaces:
- **Profile page** (`PublicNutritionistLive.Show`) gained an **"Articles by …"** section listing
  `list_published_articles_for_profile/1`.
- **Sitemap** (`sitemap_controller.ex`) emits one localized entry per published article
  (`/nutritionists/:profile_slug/articles/:slug`), joined to public profiles only.

## Files

**Core (`apps/mehungry`)**
- `lib/mehungry/professionals/{article,article_paragraph,article_reference}.ex`
- `lib/mehungry/professionals.ex` — article/paragraph/reference context functions
- `lib/mehungry/food/foundemental_foods.ex` + `food.ex` — `search_species/1`
- `lib/mehungry/literature.ex` — `fetch_and_upsert_study/1`
- `priv/repo/migrations/20260903000001_*`, `..002_*`, `..003_*`

**Web (`apps/mehungry_web`)**
- `lib/mehungry_web/live/nutritionist_live/{articles,article_editor}.ex`
- `lib/mehungry_web/live/public_nutritionist_live/article.ex` (+ Articles section in `show.ex`)
- `lib/mehungry_web/router.ex`, `views/layout/layout_view.ex` (sidebar),
  `controllers/sitemap_controller.ex`

**Tests**
- `apps/mehungry/test/mehungry/professionals_test.exs` — article CRUD, slug, ordering, reference
  FK validation
- `apps/mehungry/test/mehungry/literature/fetch_study_test.exs` — PMID fetch (Entrez stubbed via
  `:entrez_http_adapter`), cache hit, invalid PMID
- `apps/mehungry_web/test/mehungry_web/live/nutritionist_live/article_test.exs` — create → fill →
  cite disease → publish, public dead render + JSON-LD, draft redirect

## Scope notes (v1)

Single-language (no per-language article translation; canonical only). Plain paragraph body +
heading (no rich text / markdown / inline entity autolinking). No comments/reactions. These are
deliberate deferrals, not blockers.
