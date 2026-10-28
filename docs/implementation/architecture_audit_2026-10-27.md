# Architecture Audit — 2026-10-27

A whole-system audit of the Mehungry umbrella: (1) **documentation coverage** —
does every major feature have its architectural decisions written down in
`docs/implementation/*`? — and (2) an **assessment of the overall architecture**
(strengths, risks, drift). Produced by reading all of `docs/features/` +
`docs/implementation/` and cross-checking against the code and `fly.toml`.

> Scope note: this is an engineering-side review of *structure and documentation*,
> not a security pen-test or a correctness review of any single feature. Findings
> marked **✅ fixed in this pass** were corrected while writing this audit.

---

## 1. Executive summary

- **The architecture itself is sound and unusually well-documented for its size.**
  The umbrella split, the permanent `defdelegate` facades, the two sanctioned
  runtime seams, the config-key provider seams (`:instagram_client`,
  `:social_media_publisher`, `:storage_impl`, `:compound_plausibility_judge`,
  `:extractor_client`, …), and the Oban-UI-connected pattern are consistently
  applied and mostly documented to a high standard.
- **The biggest documentation problem is not the science pipeline (which is
  over-documented) — it's the core consumer loop.** Several large, shipped,
  flagship contexts have **no implementation doc at all**: `History`/Calendar
  (767 LoC + 7 schemas), `Posts`/feed (1,323 LoC), `PublishedPlans` (690 LoC),
  `Inventory`/basket (535 LoC), `Friends`, `BetaSignups`. These are the surfaces a
  new engineer is most likely to touch, and the only record of their design
  decisions is scattered across memory + `CLAUDE.md` + the mobile API spec.
- **Two canonical infra docs had drifted to describe the *wrong platform*** (AWS
  ECS/RDS) and a **removed** observability subsystem as current. These are
  architectural-decision docs that were actively misleading. **✅ fixed in this
  pass** (`architecture.md`, `operations.md`, + stale banners on the two
  observability docs).
- **~40% of `docs/implementation/science/` describes dormant, decommissioned
  code.** This is correctly banner-flagged (Phase 1, 2026-10-26) and intentional
  (decommission-in-place), but it's now the single largest doc cluster and
  disproportionate to its live footprint (one condition-seeded crawl + `/analyze`
  ingestion).

---

## 2. Documentation coverage matrix

Every core context (top-level module in `apps/mehungry/lib/mehungry/`) and major
web surface, mapped to its implementation doc. **L** = live, **D** = dormant
(decommissioned-in-place).

| Context / feature | LoC¹ | State | Implementation doc | Verdict |
|---|---|---|---|---|
| `Food` (recipes/ingredients/nutrients/units/search) | large | L | `food/*` (8 docs) + `entities/*` | ✅ excellent |
| `Accounts` | large | L | `users/accounts.md` + `entities/user.md` | ✅ |
| `Health` (advice reads) | large | L/D | `science/health_recommendations.md` + phase/pubtator | ✅ (reads live; derivation dormant) |
| `Literature` / `Chemistry` | large | L/D | `science/*` (10 docs) | ✅ (over-documented; see §5) |
| `AI` (agents/bot/images/embeddings) | large | L | `ai/*` (10 docs) | ✅ excellent |
| `MealBlueprints` | large | L | `features/meal_blueprints*.md` | ✅ |
| `Professionals` (profiles/booking/articles/clients/research notes) | large | L | `features/professionals/*` + `professionals/*` | ✅ excellent |
| `Subscriptions` / `Billing` | med | L | `features/subscriptions_billing.md` + payments | ✅ |
| `Notifications` | 138 | L | `notifications_system.md` | ✅ |
| `FoodData` (MyPlate/Gutenberg/UniTools/USDA importers) | large | L | `food/*_import.md` (3) | ✅ |
| `Storage` | — | L | `infrastructure/object_storage.md` | ✅ |
| `Languages` | — | L | `localization.md` + `translation_gates.md` | ✅ |
| `Meta` (session metrics) | — | L | `app_status.md` + `infrastructure/google_analytics.md` | ⚠️ partial (no context doc) |
| **`History` / Calendar self-tracker** | **767 + 7 schemas** | **L** | **✅ NEW `history_calendar.md`** | **closed this pass** |
| **`Posts` / feed / comments / votes** | **1,323** | **L** | **✅ NEW `posts_feed.md`** | **closed this pass** |
| **`PublishedPlans`** (public weekly plans, share card, feed post) | **690** | **L** | **✅ NEW `published_plans.md`** | **closed this pass** |
| **`Inventory`** / shopping basket | **535** | **L** | **✅ NEW `inventory_basket.md`** | **closed this pass** |
| **`Friends`** (follow/friend graph) | **226** | **L** | **— partial (accounts.md §follow)** | **⚠️ thin (open)** |
| **`BetaSignups`** / `/trial` Android testing | **143** | **L** | **— only `CLAUDE.md`** | **⚠️ thin (open)** |
| `Search` (`RecipeSearch` + `RecipeVectorSearch`) | 34 + web | L | partial (`ai_agents.md`, `food/ingredient_search.md`) | ⚠️ no front-door |
| `Feedback` | small | L | mobile spec §17 only | ⚠️ minor |
| `Plans` (legacy meal plans) | — | L? | — none | ⚠️ **status unclear** (see §4) |
| `Settings` / `Extractor` client | small | L | `features/.../research_search.md` (partial) | ⚠️ minor |
| Science *generation* pipeline | large | **D** | `science/*` (10 docs, banner-flagged) | ✅ (but see §5) |
| Observability (DIY) | — | **removed** | `observability.md` (current) + 2 stale | ✅ fixed banners this pass |

¹ Context module line counts only (schemas/LiveViews extra); "large" where the
context spans many files.

**Coverage headline:** of the live consumer core, **5 major contexts
(`Posts`, `PublishedPlans`, `Inventory`, `History`, `Friends`) totalling ~3,700
LoC had zero or near-zero implementation docs.** The science/AI/professional
subsystems are documented far more thoroughly than the loop the product's own
`normal_user.md` says most users actually live in.

---

## 3. Documentation drift (documented ≠ reality)

| # | Doc | Drift | Status |
|---|---|---|---|
| D1 | `infrastructure/architecture.md` | Said "AWS ECR → ECS; PostgreSQL 14 on RDS". App runs on **Fly.io + Supabase** (`fly.toml`, app `m3hungry`/`lhr`). Oban queue list + cron (`TelemetryPrunerWorker`) also stale. | **✅ fixed** |
| D2 | `infrastructure/operations.md` | Same AWS-ECS deploy pipeline staleness. | **✅ fixed** |
| D3 | `infrastructure/scaling_metrics.md` | Entire doc assumes the **removed** `MetricsBuffer`/`telemetry_snapshots` layer is live ("✅ Persisted"). | **✅ banner added** |
| D4 | `infrastructure/observability_review_2026-07-05.md` | Reviews a subsystem that no longer exists. | **✅ banner added** |
| D5 | `ai/ai_agents.md` | Text says image gen uses `gpt-image-1` and a "DALL-E 3" moduledoc; `ai/ai.md` documents a `gpt-image-2` **/ FLUX** provider seam (`:recipe_image_provider`). Code contains all of `gpt-image-1`, `gpt-image-2`, `flux`. | ⚠️ open — reconcile the two AI docs on the actual default + seam |
| D6 | `infrastructure/object_storage.md` | Frames Supabase cutover as "Phase 4 / grace period"; `CLAUDE.md` states Supabase is the canonical active backend. | ⚠️ open — confirm migration complete, update tense |
| D7 | `app_status.md` | Snapshot header is 2026-10-17 and still partly describes the `visits` table; the analytics-removal + newer snapshot rows (10-25) have landed. | ⚠️ low — it's a living log, mostly self-aware |

D1–D4 are the material ones: a canonical "where/how is this deployed" doc naming
the wrong cloud is exactly the kind of architectural-decision drift this audit was
asked to catch.

---

## 4. Specific structural questions surfaced

1. **`Plans` vs `MealBlueprints` vs `PublishedPlans` vs `History` — four
   "plan"-shaped contexts.** `CLAUDE.md` lists legacy `Plans` ("Meal plans and
   daily meal plans"); `MealBlueprints` is the current authoring model;
   `PublishedPlans` backs the public/profile plans; `History` is the live
   calendar. `Mehungry.Plans` is still referenced from `recipes.ex`,
   `ingredients.ex`, `professionals/meal_plan_rating.ex`, and a nutritionist
   LiveView — so it is **not** dead, but its relationship to the other three is
   undocumented. A reader cannot tell which to build on. **Recommend** one short
   doc that draws the boundary between these four.
2. **Three overlapping "social graph / client" notions** (consumer `Friends` +
   `user_follows`, the nutritionist↔client `TutorClientAssignment`, and the PII
   `ProfessionalClient` record) — flagged already in `normal_user.md` and the
   nutritionist assessment memory, but not reconciled in an implementation doc.
3. **`messages_live`** (client↔nutritionist messaging) is backed by
   `Professionals.AssignmentMessage` — resolved during this pass and noted in
   `plans_vocabulary.md`; still deserves a line in a `Professionals` mechanics doc.
4. **`food_products` / OpenFoodFacts** context exists (`food_products.ex` +
   `food_products/`) with no doc and no mention in `food/food.md`'s sub-module
   table.

---

## 5. Assessment of the overall architecture

### Strengths (keep doing this)

- **Umbrella boundary is clean and enforced in spirit.** `mehungry_web → mehungry`
  only; the two documented runtime seams (`:social_media_publisher`,
  `:endpoint_module`) are the *only* way core reaches web, and both are
  `Application.get_env/3` lookups resolved at call time. This is textbook.
- **Facade discipline** (`Food`, `Accounts`, `Users`) genuinely protects call
  sites; the "add a `defdelegate` when you add a public fn" rule is stated in
  three places and followed.
- **Provider seams everywhere money/network/LLM is involved**, each stubbed in
  test via a config key. This is the single most repeated and most valuable
  pattern in the codebase and it's well documented.
- **"Validate, don't trust" + "the submit tool is the only exit"** for AI agents,
  with DB-provenance gates, is a mature answer to LLM hallucination and is backed
  by real regression tests (the Cacio-e-Pepe wrong-ingredient bug write-up is a
  model post-mortem).
- **The YMYL boundary is treated as a first-class architectural invariant**, not a
  UI toggle: condition pages are off the public router + sitemap, the consumer
  health opt-in table was *dropped* (not just hidden), and every doc that touches
  it repeats the rule. Backed by `legal_review_2026-10.md`.
- **Oban concurrency is deliberately capped at 13** to fit the Supabase pool — a
  real, diagnosed production constraint (`oban_production_diagnostics.md`), not a
  guess.
- **Reference-architecture extraction** (`oban_ui_connected_worker.md`) shows the
  team abstracts proven patterns rather than re-deriving them — the research
  ingestion, hashtag reconcile, portion generation, and GI matching all reuse it.

### Risks / weaknesses

- **R-A: The core consumer loop is the least-documented part of the system**
  (§2). The feature docs (`normal_user.md`) describe *what* it does; no
  implementation doc describes *how* `History`/`Posts`/`Inventory` are built, what
  the denormalization decisions are (`ingredient_user_meals.nutrients`,
  `recipe_user_meals.recipe_nutrients`), or the week-scoped loading
  performance work. This is where drift and bugs will be most expensive and least
  catchable.
- **R-B: Documentation mass is inverted relative to live footprint.** `science/`
  is 10 docs (~2,400 lines) describing mostly-dormant code; the live calendar got
  zero. A newcomer reading `docs/implementation/` front-to-back would badly
  mis-estimate where the product's weight is. The dormant-code docs are correctly
  banner-flagged, but consider moving the fully-dormant generation docs into a
  `science/_dormant/` subfolder so the live surface (research search ingestion)
  isn't buried.
- **R-C: Dormant-but-not-dropped code is a standing liability.** Phase 1 left
  Chemistry, PubTator, compound/recommendation candidates, GI, and the
  `mehungry_local_ai` app as dormant tables + modules. That's a deliberate,
  reversible choice — but every one is still compiled, still has tests, and still
  shows up in greps, raising the cost of every future refactor. The Phase 2
  hard-delete should be scheduled, not open-ended.
- **R-D: Observability regressed to baseline by choice.** The DIY layer was torn
  out for good reasons, but the replacement (PromEx + LiveDashboard, no retention,
  no alerting, no error tracking) means **production incidents are invisible
  unless someone is watching `/dashboard`**. For a 2-machine Fly deployment with
  real (if small) paying users, "no alerting and no persisted error history" is
  the biggest operational gap. `scaling_metrics.md`'s saturation framing is still
  the right shopping list — it just needs re-pointing at an external Prometheus.
- **R-E: Legal/compliance items are code-level, not doc-level, and still open.**
  `legal_review_2026-10.md` §4 lists the erasure cascade gap
  (`Accounts.delete_user` omits nutritionist client PII, `nilify_all` leaves
  health data behind), GA-loads-before-consent, and medical-device qualification
  as *blocking before scaling*. These are architecture decisions (data model +
  consent gating) masquerading as a legal to-do. The erasure cascade in
  particular is a correctness/GDPR bug, not a disclaimer.
- **R-F: Leftover AWS artifacts** (`task-definition.json`, `migrator/`) alongside
  the live `fly.toml` are a trap — a future operator could edit the wrong one.
  Either delete them or move them under a clearly-labelled `legacy/` path.

---

## 6. Recommendations (prioritized)

**Documentation (close the gaps this audit was asked to close):**

1. **✅ done this pass:** `history_calendar.md` (the flagship gap), + the four
   infra drift fixes (D1–D4).
2. **✅ done:** `posts_feed.md` — the `Post` model, home feed, comments/answers,
   votes, and the context-level notification emission.
3. **✅ done:** `published_plans.md` — the public snapshot + weekly-plan **share
   card + feed post** flow.
4. **✅ done:** `inventory_basket.md` — basket + `create_basket_for_range/4` +
   the shared `aggregate_meal_ingredients/1`.
5. **✅ done (partial):** `plans_vocabulary.md` draws the `Plans` /
   `MealBlueprints` / `PublishedPlans` / `History` boundary (§4.1) and records
   that messaging lives in `Professionals.AssignmentMessage`. **Still open:** thin
   notes for `Friends`, `BetaSignups`, and the `food_products`/OpenFoodFacts
   context.
6. **Reconcile D5/D6** (AI image provider default/seam; storage migration tense) —
   still open.

**Architecture / operations:**

7. **Add minimal alerting + error capture** (R-D) — even a single "no metrics
   flushed / 5xx spike" signal and Sentry-or-equivalent would close the largest
   operational blind spot. This is a deliberate re-add, not a resurrection of the
   DIY layer.
8. **Fix the erasure cascade** (R-E / legal R4) — it's a data-model bug with GDPR
   exposure; make deletion a POST with re-auth and cascade nutritionist PII.
9. **Schedule the science Phase-2 hard-delete** (R-C) or explicitly timebox the
   dormancy, so the dead-weight cost is bounded.
10. **Delete or quarantine the AWS task definitions** (R-F).

---

## 7. What was changed in this pass

- `infrastructure/architecture.md` — platform (Fly.io/Supabase), Oban queues +
  cron corrected.
- `infrastructure/operations.md` — deploy pipeline corrected to Fly.io.
- `infrastructure/scaling_metrics.md`, `observability_review_2026-07-05.md` —
  stale banners pointing at `observability.md`.
- **New implementation docs** closing the live-consumer-core gap:
  `history_calendar.md` (Calendar/`History`), `posts_feed.md` (`Posts`/feed),
  `published_plans.md` (`PublishedPlans`), `inventory_basket.md` (`Inventory`),
  and `plans_vocabulary.md` (the four-plan-context boundary).
- `README.md` — index updated for all new docs.

Still **recommended, not done** — §6 items 6–10 (reconcile the AI-image/storage
doc drift; thin notes for `Friends`/`BetaSignups`/`food_products`) plus the
ops/architecture items that need a product or ops decision: **alerting + error
capture** (R-D), the **GDPR erasure cascade** fix (R-E), scheduling the **science
Phase-2 hard delete** (R-C), and quarantining the leftover **AWS task
definitions** (R-F).
