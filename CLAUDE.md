# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mehungry is a food/recipe social platform built as a **Phoenix Umbrella** application with two apps:
- `apps/mehungry` — core domain layer (Ecto schemas, contexts, business logic)
- `apps/mehungry_web` — Phoenix web layer (LiveViews, controllers, components)

Deployed via Docker → GitHub Actions → AWS ECR → AWS ECS, with PostgreSQL on AWS RDS (v14).

## Development Commands

```bash
# Initial setup (deps + DB create + migrate + seed)
mix setup

# Start server
mix phx.server
iex -S mix phx.server

# Database
mix ecto.migrate
mix ecto.reset          # drop + recreate + migrate + seed

# Build assets (dev)
mix assets.build

# Run all tests
mix test

# Run a single test file
mix test apps/mehungry/test/mehungry/food_test.exs

# Run a single test by line number
mix test apps/mehungry/test/mehungry/food_test.exs:42

# Static analysis
mix credo
mix dialyzer
```

## Architecture

**Scientific pipeline** (`Chemistry` → `Literature` → `Food.*` compound layers →
`Health`): how the discover → curate → advise stages compose, plus the ordered
"run X, then run Y" setup runbook, is in **`docs/scientific_pipeline.md`**.

### Domain Contexts (`apps/mehungry/lib/mehungry/`)

| Context | Responsibility |
|---|---|
| `Accounts` | Facade over `Accounts.{Auth, OAuth, Profiles, Rules, Admin, UserContent, Grading}` — see `docs/accounts.md`. `Mehungry.Users` is a deprecated facade over the same sub-modules |
| `Food` | Facade over `Food.{Recipes, Ingredients, IngredientQueries, Nutrients, Measurements, Categories, Localization, Engagement}` — see `docs/food.md`. Bioactive-compound knowledge is a sidecar under this facade: qualitative facts (`Food.Compounds`, "Spinach contains Oxalate") in `docs/food_compounds.md`, and immutable quantitative measurements (`Food.CompoundMeasurements`, "Spinach, Oxalate, Raw: 750 mg/100g") in `docs/compound_measurements.md`, and read-only evidence summaries over those measurements (`Food.EvidenceAggregation.summarize/2` → `IngredientCompoundSummary` with mean/range/variance + an auditable evidence score) in `docs/evidence_aggregation.md`, and the curation step that turns evidence into facts (`Food.CompoundCandidates` — derives scored **species**↔compound candidate relationships (keyed on `FoundementalFoodSpecies`, not ingredient) from PubTator co-occurrence + measurements, each citing the reference studies it came from via `SpeciesCompoundCandidateStudy`; auto-promotes strong ones over a config threshold or by admin review at `/professional/compound-candidates` into `SpeciesCompoundRelationship` facts (`Food.SpeciesCompounds`), feeding them back as targeted crawl terms; a `:non_dietary_compounds` blocklist keeps assay reagents like DPPH out) in `docs/compound_candidates.md`. All `Food.*` compound layers are **facts only**; dietary advice that reads these facts lives in the separate `Health` context. USDA-backed ingredients are curated onto a `Food.FoundementalFoodSpecies` (name + `scientific_name` + `variety`/`family`) in the USDA Schema view (`/professional/usda-schema`); the species' `scientific_name` is what drives the literature crawl |
| `Health` | Health-recommendation knowledge — conditions linked to bioactive **compounds** (never to species or ingredients) as dietary advice: `Health.Condition` registry + `Health.CompoundRecommendation` ("Kidney Stones: avoid Oxalate", "IBS: limit FODMAP") with `recommendation`/`severity`/`evidence_level`/`source`. `Health.species_for_condition/2` (primary) resolves the implicated **`FoundementalFoodSpecies`** at read time via the shared compound through `SpeciesCompoundRelationship`; `Health.ingredients_for_condition/2` derives the ingredients **strictly through those species** (there is no condition↔ingredient or fact↔ingredient link). This is the advice layer the `Food.*` fact layers defer to. Recommendations are hand-curated at `/professional/health` **or** derived from literature: `Health.RecommendationCandidates` mirrors `Food.CompoundCandidates` to turn PubTator's directional chemical↔disease relations (`Literature.StudyEntityRelation`) into scored, **review-gated** `CompoundRecommendationCandidate`s (negative-correlation → suggest *encourage*, positive → *avoid*); an admin confirms direction/severity to promote into a `CompoundRecommendation` (`source: "literature"`) — never auto-promoted. Diseases resolve to conditions via `Health.ConditionResolver` + `condition_identifiers` (MeSH). See `docs/health_recommendations.md`, `docs/pubtator_relations_recommendations.md` |
| `Chemistry` | External chemical-identity resolver for the `Food.Compounds` registry — `Chemistry.Resolver.resolve/2` is the identifier-first entry point (looks up by `(namespace, identifier)`, e.g. a MeSH id; cross-references PubChem CID/ChEBI/CAS/InChIKey; writes normalized `compound_identifiers` rows). `import_compound/2` (name→CID via PubChem) is the name-only fallback. Raw payloads in `pubchem_responses`, provenance in `compound_sources`. See `docs/chemistry.md` |
| `Literature` | Two NCBI adapters over the study registry. **Entrez (PubMed) discovery** — crawls each `FoundementalFoodSpecies` by its curated `scientific_name × (linked compounds ∪ keywords)`, fanning each discovered `ScientificStudy` (PMID-keyed) out to every ingredient curated onto the species via `StudyIngredient` (plus `StudyCompound`); ledger `literature_crawl_attempts` is keyed on `(foundemental_species_id, search_term)`; `entrez_responses`, `LiteratureCrawlWorker`. **PubTator3 extraction** — annotates a `ScientificStudy` into `StudyEntityMention` facts (Chemicals/Species/Diseases), chemicals resolved via `Chemistry.Resolver`; also parses the payload's directional `relations` array into `StudyEntityRelation` rows (chemical↔disease etc.) with both endpoints resolved (chemical→compound, disease→condition), `remine_relations/0` back-fills them from stored payloads; `pubtator_responses`, `pubtator_annotation_attempts`, `PubTatorAnnotationWorker`. Both on the `:imports` queue; discovery/extraction only — never asserts dietary facts (the relations feed the review-gated `Health.RecommendationCandidates`). See `docs/literature_discovery.md`, `docs/pubtator.md` |
| `Inventory` | Shopping baskets and basket items |
| `Plans` | Meal plans and daily meal plans |
| `Posts` | Posts, comments, comment answers, votes |
| `Search` | Full-text recipe search |
| `Survey` | User dietary preference surveys |
| `Languages` | Multi-language translations for ingredients and units. App-wide localization (locale-prefixed URLs `/en/…`·`/el/…`, `MehungryWeb.Locale` + `SetLocale` plug + `RestoreLocale` on_mount, Gettext UI strings, hreflang/canonical) is in **`docs/localization.md`** |
| `Meta` | Visit tracking |
| `History` | User activity history |
| `Professionals` | Nutritionist profiles, client invitations, assignments, appointments, meal plan ratings |
| `Subscriptions` | Subscription tiers, Stripe integration, AI feature quota enforcement — see `docs/subscriptions_billing.md` |
| `AI.Bot` | Managed social media recipe pipeline — monthly configs, review queue, translations, post logs |
| `Billing` | Stripe checkout sessions and webhook handling (`Billing.StripeHandler`) — see `docs/subscriptions_billing.md` |
| `Social` | Social platform layer (`social/`): `Social.Publisher` fan-out (behind `Social.PublisherBehaviour`), `Social.{Facebook, Pinterest}` HTTP clients, and the `Social.Instagram` context — see `docs/social_publishing.md` |
| `FoodData` | External food-data sources (`food_data/`): `FoodData.Usda.{SearchClient, FdcClient, FoodParser, SeedFileParser}`, `FoodData.OpenFoodFacts.*`, `FoodData.SpoonacularImporter` |
| `S3` | The single ExAws S3 wrapper (`s3.ex`) — use it instead of inline `ExAws.S3` calls |

**Facade convention:** `Mehungry.Food`, `Mehungry.Accounts`, and
`Mehungry.Users` are permanent defdelegate facades — public functions never
break when internals move. New code may call sub-modules directly; when adding
a public function to a sub-module, add a matching `defdelegate` to the facade.
Architecture overview: **`docs/architecture.md`**.

**Cachex** runs three named caches started in `Mehungry.Application`:
- `:recipes_cache` — LRU, limit 150
- `:cache_user_tokens`
- `:geo_cache` — LRU, limit 5000

### AI Subsystem (`apps/mehungry/lib/mehungry/ai/`)

A custom Anthropic API layer — do not use raw HTTPoison calls for AI work:

- `AI.Client` — shared HTTP client for the Anthropic Messages API. Handles auth, retries (exponential backoff on 529 rate-limit and timeouts), and response parsing. Default model: `claude-haiku-4-5-20251001`, default max_tokens: 2048.
- `AI.Agent` — generic tool-use loop. Runs a conversation until `end_turn` or `max_iterations` (default 10). Accepts a `handler` function `fn(tool_name, input, context) -> result` and dispatches tool calls automatically.
- `AI.Agents.RecipeAgent`, `MealPlanAgent`, `NutritionistAgent` — domain-specific agents built on `AI.Agent`.
- `AI.ImageGenerator`, `AI.IngredientTranslator`, `AI.RecipeTranslator`, `AI.MealPlanGenerator` — standalone AI utilities.

**Bumblebee/EXLA is gone from the deployed apps.** The local extractive-QA model for measurement extraction now lives in a separate, **non-deployed** umbrella app, `apps/mehungry_local_ai` (`MehungryLocalAi.{QA, PMC, Extractor, Client}` + `mix local_ai.extract`), which runs on a GPU box and talks to the server only over the token-guarded `/api/local_ai/*` REST API — it does PMC fetch + parse + QA extraction locally and posts full text + candidates back. It's excluded from the release and the Docker build, so `nx`/`exla`/`bumblebee`/`xla` are never fetched or compiled in production. See `docs/measurement_extraction.md`. (`AI.EmbeddingServer` was dead code and was removed; the surviving recipe-embedding path uses the OpenAI API + pgvector, no Nx.)

Config key: `:anthropic_api_key` (read from `ANTHROPIC_API_KEY` env var in `runtime.exs`).

### AI Bot Pipeline (`apps/mehungry/lib/mehungry/ai/bot/`)

Automated recipe-to-social-media pipeline:

1. `AiBotConfig` — monthly config with theme, bot user, and `publish_times` map (meal_type → language → UTC time string).
2. `WeekConfig` / `DayConfig` — optional sub-configs to override week/day themes.
3. `AiBotRecipe` — tracks each generated recipe with status: `pending_review → approved/rejected → published`.
4. Oban cron fires `DailyRecipeGenerationWorker` at **2am UTC daily** → generates one recipe per meal type via `RecipeAgent` → schedules `RecipePublishWorker` jobs (one per meal × language) at the times in `publish_times`.
5. Admin reviews at `/professional/ai-bot/review` before publish jobs run.
6. `RecipePublishWorker` calls `Mehungry.Social.Publisher.publish_recipe/5` (mockable via app config key `:social_media_publisher`) — see `docs/social_publishing.md`.
7. `AI.Bot.Notifier` sends admin email when batch is ready for review.

### Subscription Tiers (`Mehungry.Subscriptions`)

Three tiers enforced via `check_quota/2` and `record_usage/2`:
- `"free"` — 0 recipe generations / 0 meal plans per month
- `"m3hungry_plus"` — 15 / 4 per month (consumer premium, billed via Stripe)
- `"pro"` — 30 / 10 per month (nutritionist tier, billed via Stripe)

The owner email (`nikolisgal@gmail.com`) bypasses all quota checks. Use `Subscriptions.pro?/1` and `Subscriptions.nutritionist?/1` for gate checks.

Stripe events are handled via `POST /webhooks/stripe` → `StripeWebhookController` → `Billing.StripeHandler`.

### Oban Queues

```
default:            10 concurrent  — ingredient translation, recipe publishing
ai_agents:           2 concurrent  — recipe generation, translation, image generation, nutritionist agent
mailers:             5 concurrent  — email
imports:             2 concurrent  — literature crawl, PubTator annotation, candidate derivation
```

Full-text (PMC) + measurement extraction is **no longer a server-side Oban pipeline** — it moved to the non-deployed `apps/mehungry_local_ai` service, which posts full text + review-gated candidates back over `/api/local_ai/*`. `/professional/science` shows read-only status; review stays at `/professional/compound-candidates`. See `docs/measurement_extraction.md`.

Cron: `InstagramTokenRefreshWorker` at `30 1 * * *`, `DailyRecipeGenerationWorker` at `0 2 * * *`, `TelemetryPrunerWorker` at `0 3 * * *`, `PipelineWatchdogWorker` every 10 min (resumes any science-pipeline run whose single-threaded chain broke — see `Mehungry.Science.PipelineWatchdog` + `docs/scientific_pipeline.md`).

### Instagram Integration (`Mehungry.Social.Instagram`)

Core-app context for the Instagram Graph API: `Social.Instagram.Token` (token map lifecycle/status), `Social.Instagram.Caption` (2200-char capped captions), `Social.Instagram.Client` behind `Social.Instagram.ClientBehaviour` (stubbed in tests via `:instagram_client` config key). Long-lived tokens are refreshed daily by `InstagramTokenRefreshWorker`; invalid tokens are marked stale and surface as "reconnect" in `/professional/ai-bot/social`. `RecipePublishWorker` publish failures return `{:error, _}` for Oban retries, skipping platforms that already have an `"ok"` post log (manual re-publish passes `force: true`). The publisher seam is typed by `Mehungry.Social.PublisherBehaviour` (`:social_media_publisher` config key).

### Observability

Full operator's manual: **`docs/observability.md`** (architecture, metric reference, diagnostic playbooks, limitations). Summary: telemetry events fan out to live LiveDashboard metrics (`MehungryWeb.Telemetry`), a persistent snapshot store (`Mehungry.Telemetry.MetricsBuffer` → `telemetry_snapshots`, 5-min aggregates, 30-day retention), a DIY error tracker (`Mehungry.Telemetry.ErrorTracker` → `error_events`, fingerprint-deduped), and warning logs (`[SlowQuery]` ≥500ms, `[SlowRequest]` ≥2s, `[ProcessWatchdog]` mailbox ≥1000). Everything is viewed at `/dashboard` (admin-gated via `config :mehungry, :admin_email` + `MehungryWeb.Plugs.RequireAdmin`), including custom pages Metrics History and Errors. Error tracking is deliberately in-app (no Sentry) and dashboard-only (no alerting).

### Web Layer (`apps/mehungry_web/lib/mehungry_web/`)

All authenticated UI is built with **Phoenix LiveView**. Live sessions in `router.ex`:

| Session | `on_mount` | Routes |
|---|---|---|
| `:default` | `UserAuthLive` | `/basket`, `/calendar`, `/create_recipe`, `/upgrade`, `/posts`, etc. |
| `:default2` | `AdminAuthLive` | `/professional/**` (admin/internal tools) |
| `:nutritionist` | `NutritionistAuthLive` | `/nutritionist/**` (dashboard, clients, appointments) |
| `:maybe` | `MaybeUserAuthLive` | `/home`, `/browse`, `/search`, `/profile`, `/foods` |
| `:default3` | none | `/welcome` (landing) |

**Authentication** uses Ueberauth with Facebook, Google, and Instagram OAuth. Session state is injected via `on_mount` callbacks. `BotOAuthController` handles OAuth for bot social accounts (`/auth/bot/target/:bot_user_id/:provider`).

**Presence** (`MehungryWeb.Presence`) tracks active users and records visits. Live views opt in with `use MehungryWeb.Presence, :user_tracking`.

### Frontend

- **Tailwind CSS** + **DaisyUI** for styling
- **Alpine.js** for client-side interactivity
- **jQuery** + **Select2/Selectize** — legacy select components (being phased out)
- **Vega-Lite** for charts via `Hooks.VegaLite` and `Hooks.ResponsiveChart` JS hooks
- **esbuild** bundles JS; `mix assets.build` / `mix assets.deploy` compile assets

Client hooks: `apps/mehungry_web/assets/js/hooks.js`. Navigation active-state handled by a JS `Proxy` intercepting URL changes (`navigation.js`).

**Google Analytics (GA4)**: Consent Mode v2-gated `gtag.js` in `head.html.heex`, manual `page_view` tracking for LiveView SPA navigation, and a `MehungryWeb.GoogleAnalytics.track/3` seam for custom events — see **`docs/google_analytics.md`**.

**Design system**: warm-charcoal/paprika/basil token set (`ink`, `paprika`, `basil`, `parchment` in `tailwind.config.js`) rolled out to `/profile` only so far — palette rationale, component rules, and the CSS-variable pattern for retheming shared components (e.g. `SelectComponent`) without breaking their other call sites are in **`docs/design_system.md`**.

### Modal Approaches

Three coexisting patterns — prefer option 3 for new code:
1. CSS + `Phoenix.LiveView.JS` — recipe browser
2. CSS + client Hooks — elsewhere
3. `core_components.ex` modal — **preferred for new code**

## Testing Layers

1. **Unit** — `ExUnit` in `apps/mehungry/test/`
2. **Integration/smoke** — `ExUnit` with `ConnCase`/`LiveViewTest` in `apps/mehungry_web/test/`
3. **Functional** — Wallaby (browser-driven) in `apps/mehungry_web/test/features/`

Wallaby tests require a `chromedriver` binary on `PATH` (no longer vendored in the repo — see `docs/operations.md`).

## LiveView Conventions

- Build Live Components with a clear division between **View (Render)** and **Update** code.
- Define view functions in the order they are invoked, starting with `render`.

**Hierarchical Selection pattern** — when picking the first non-nil value from a priority-ordered set of sources:

```elixir
case {first, second, third} do
  {nil, nil, nil} -> default
  {nil, nil, third} -> third
  {nil, second, _} -> second
  {first, _, _} -> first
end
```

## Environment Variables

Required at runtime:
- `DATABASE_URL` — PostgreSQL connection string (watch for stray spaces when copy-pasting)
- `SECRET_KEY_BASE`
- `ANTHROPIC_API_KEY` — for all AI features
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRO_PRICE_ID`, `STRIPE_PRO_YEARLY_PRICE_ID` (consumer `m3hungry_plus` tier), `STRIPE_NUTRITIONIST_PRICE_ID`, `STRIPE_NUTRITIONIST_YEARLY_PRICE_ID` (nutritionist `pro` tier)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ASSETS_BUCKET_NAME`
- `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `INSTAGRAM_CLIENT_ID`, `INSTAGRAM_CLIENT_SECRET`
- `PINTEREST_CLIENT_ID`, `PINTEREST_CLIENT_SECRET`; `PINTEREST_ENV` selects the API environment — `live` for the real API, anything else (or unset) for the sandbox
- `FDC_API_KEY` — required for USDA food lookups (basket search + AI ingredient creation); there is no fallback key
- `OPENAI_API_KEY` — optional (embeddings, cover images)
- `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` — Cloudflare Turnstile CAPTCHA on registration (optional; verification is skipped when the secret key is unset)

## Deployment Notes

- PostgreSQL version 14 is required; newer versions may not work with the current ECS setup.
- The migrator app (`migrator/`) runs DB migrations as a separate ECS task.
- Task definitions are in `task-definition.json` and `migrator-task-definition.json`.
- AWS region: `eu-central-1`.
