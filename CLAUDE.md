# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mehungry is a USDA-backed nutrition platform **led by the professional nutritionist** (discoverable profile + client/appointment workspace + AI meal-plan drafting), with a consumer food/recipe layer as the second ring. **For the product's purpose, audience, positioning, and non-negotiable principles, read `docs/features/product_foundation.md` first** — it's the source of truth every product decision traces back to. Built as a **Phoenix Umbrella** application with two apps:
- `apps/mehungry` — core domain layer (Ecto schemas, contexts, business logic)
- `apps/mehungry_web` — Phoenix web layer (LiveViews, controllers, components)

Deployed on Fly.io (Docker image → Phoenix release). Canonical host is `www.m3hungry.com`.

**Documentation layout** (see `docs/README.md`): docs live in four top-level folders —
- `docs/features/` — **functional features**: the value delivered to customers (nutritionists + normal users). Vision, positioning, personas, and what each feature does for the user.
- `docs/growth/` — **surfacing / go-to-market**: work that isn't direct customer value but gets the product found (SEO, hashtags, social publishing + copy, growth plan).
- `docs/implementation/` — **how it's built + its state**: implementation specifics for the features and growth work, with domain subfolders `science/`, `food/`, `ai/`, `entities/`, `infrastructure/`, `professionals/`, plus API spec, localization, notifications, status.
- `docs/reference_architecture/` — **proven reusable patterns** to follow when building a new feature of the same shape.

The axis is per-document: a whole doc is filed by its center of gravity (what it's *mostly* about), not split across folders.

**Keeping docs in sync — do this as part of the same change, not later:** when you touch code, update the doc that describes it in the same commit. Specifically: a **feature behavior / UX / scope** change → update the matching `docs/features/` doc; an **SEO / hashtag / social-publishing** change → `docs/growth/`; a **schema / context / worker / pipeline / infra** change → the matching `docs/implementation/` domain doc (and `docs/implementation/entities/` when an entity's schema changes); any `/api/v1` route/action/serializer change → `docs/implementation/new_dec_specs/mobile_api_spec.md` (the mobile contract — it must never drift); a new reusable design pattern → add it to `docs/reference_architecture/`. If a change spans several, update each. Docs and code drifting apart is treated as a bug.

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
`Health`): overview of how the discover → curate → advise stages compose, the
external authorities they draw on, and the invariants, is in
**`docs/implementation/science/science.md`** (the front door to the `docs/implementation/science/` folder); the
composed flow diagram and the ordered "run X, then run Y" setup runbook are in
`docs/implementation/science/scientific_pipeline.md`.
> **Decommissioned (research-search reshape, Phase 1, 2026-10-26):** the *generation* half of this
> pipeline — species-seeded crawl, PubTator annotation, compound/recommendation **candidate
> derivation**, Chemistry/PubChem, glycemic-index — had its admin UIs
> (`/professional/{science,literature,compound-candidates}`) and the inbound
> `/api/local_ai/*` seam **removed**; `PipelineWatchdog`/`RunReconciler` now cover only the
> condition-seeded crawl. Contexts, Oban workers, schemas, and tables are **dormant, not dropped**.
> What's live: the **condition-seeded crawl + extractor `/analyze` ingestion** feeding the
> nutritionist **research search** (`docs/features/professionals/research_search.md`, admin
> acquisition on `/professional/health`; nutritionist UI `/nutritionist/research` — collapsible
> research-type groups, per-paper section-outline deep-links, per-paper **"Suggested notes"** the
> nutritionist can **Save** or annotate with their **own** notes — persisted per-user in
> `research_notes` (`Mehungry.Professionals.ResearchNotes`), shown on a **"My notes"** page
> `/nutritionist/research/notes`; see `docs/features/professionals/research_notes.md` — and an in-app
> full-text **reader** `/nutritionist/research/:condition_id/paper/:study_id` with `#sec-`/`#par-`
> anchors + inline claim highlighting + a floating notes widget (save suggested notes / select a
> passage → custom note), backed by the `study_full_texts.sections` outline the enriched
> `/analyze` response carries), plus all hand-curated `Health`/`Food` advice **reads** that
> consumer features (badges, blueprints, `/foods` filter) still depend on.

**Entity data dictionary** — the canonical schema reference for the app's fundamental
entities (Recipe, Ingredient, MeasurementUnit, Nutrient, Category,
FoundementalFoodSpecies, Hashtag, User, Language) is in **`docs/implementation/entities/`**
(index: `docs/implementation/entities/entities.md`). Join/child tables are folded into their parent's
card. Other docs link there instead of re-describing schemas.

### Domain Contexts (`apps/mehungry/lib/mehungry/`)

| Context | Responsibility |
|---|---|
| `Accounts` | Facade over `Accounts.{Auth, OAuth, Profiles, Rules, Admin, UserContent, Grading}` — see `docs/implementation/users/accounts.md`. `Mehungry.Users` is a deprecated facade over the same sub-modules |
| `Food` | Facade over `Food.{Recipes, Ingredients, IngredientQueries, Nutrients, Measurements, Categories, Localization, Engagement}` — see `docs/implementation/food/food.md`. Bioactive-compound knowledge is a sidecar under this facade: qualitative facts (`Food.Compounds`, "Spinach contains Oxalate") in `docs/implementation/science/food_compounds.md`, and immutable quantitative measurements (`Food.CompoundMeasurements`, "Spinach, Oxalate, Raw: 750 mg/100g") in `docs/implementation/science/compound_measurements.md`, and read-only evidence summaries over those measurements (`Food.EvidenceAggregation.summarize/2` → `IngredientCompoundSummary` with mean/range/variance + an auditable evidence score) in `docs/implementation/science/evidence_aggregation.md`, and the curation step that turns evidence into facts (`Food.CompoundCandidates` — derives scored **species**↔compound candidate relationships (keyed on `FoundementalFoodSpecies`, not ingredient) from PubTator co-occurrence + measurements, each citing the reference studies it came from via `SpeciesCompoundCandidateStudy`; auto-promotes strong ones over a config threshold or by admin review (the `/professional/compound-candidates` UI was **decommissioned 2026-10-26, Phase 1** — context/worker/tables dormant, not dropped) into `SpeciesCompoundRelationship` facts (`Food.SpeciesCompounds`), feeding them back as targeted crawl terms; two credibility filters gate auto-promotion since document co-occurrence ≠ containment — a curatable `Compound.dietary_relevance` attribute (`dietary|non_dietary|pending`) excludes solvents/reagents/contaminants/class-terms globally, and an LLM "reality check" (`Food.CompoundPlausibility`, `:compound_plausibility_judge` seam) holds implausible pairs like *Acerola contains Ethanol* for review) in `docs/implementation/science/compound_candidates.md`. All `Food.*` compound layers are **facts only**; dietary advice that reads these facts lives in the separate `Health` context. USDA-backed ingredients are curated onto a `Food.FoundementalFoodSpecies` (name + `scientific_name` + `variety`/`family`) in the USDA Schema view (`/professional/usda-schema`, retained); the species' `scientific_name` used to drive the species literature crawl (**decommissioned 2026-10-26, Phase 1** — dormant; see `docs/features/professionals/research_search.md`). **Per-serving nutrient-claim badges** ("High in Iron", "Source of Vitamin C") are `Food.NutrientClaims` — EU Reg 1169/2011 Annex XIII NRVs (≥30% = `high`, ≥15% = `source`, per serving); written into the derived `recipes.badges` jsonb column by `Recipes.put_nutrient_info/2` alongside `nutrients` (so recomputed on every create/update via `RecipePutNutrientsWorker`; backfill with `Food.enqueue_nutrient_recalculation_for_all/0`), filterable via `Food.recipes_with_badge/2` |
| `Health` | Health-recommendation knowledge — conditions linked to bioactive **compounds** (never to species or ingredients) as dietary advice: `Health.Condition` registry + `Health.CompoundRecommendation` ("Kidney Stones: avoid Oxalate", "IBS: limit FODMAP") with `recommendation`/`severity`/`evidence_level`/`source`. `Health.species_for_condition/2` (primary) resolves the implicated **`FoundementalFoodSpecies`** at read time via the shared compound through `SpeciesCompoundRelationship`; `Health.ingredients_for_condition/2` derives the ingredients **strictly through those species** (there is no condition↔ingredient or fact↔ingredient link). This is the advice layer the `Food.*` fact layers defer to. Recommendations are hand-curated at `/professional/health` **or** derived from literature: `Health.RecommendationCandidates` mirrors `Food.CompoundCandidates` to turn PubTator's directional chemical↔disease relations (`Literature.StudyEntityRelation`) into scored, **review-gated** `CompoundRecommendationCandidate`s (negative-correlation → suggest *encourage*, positive → *avoid*); an admin confirms direction/severity to promote into a `CompoundRecommendation` (`source: "literature"`) — never auto-promoted. Diseases resolve to conditions via `Health.ConditionResolver` + `condition_identifiers` (MeSH). A parallel **nutrient** advice layer (`Health.NutrientRecommendation`, condition↔nutrient by canonical name) resolves through the **populated** per-100g USDA `IngredientNutrient` table via `Health.NutrientTargets` (label→`Nutrient` rows + threshold) — so it produces real foods where the compound facts are still empty; both engines are unioned at every read surface (`/foods` filter, recipe browse, badges, blueprint auto-suggest) and the shipped generic **"Anti-Inflammatory"** indication (`category: "dietary_pattern"`) is the first consumer. **Condition detail pages (`ConditionDetailLive`) are deliberately NOT part of the public/visible app** — they are mounted only inside the nutritionist-gated panel (`/nutritionist/conditions`), are absent from the public router and the sitemap, and must stay that way until the product formally qualifies to publish condition-specific dietary advice as a regulated medical-device / health-information service (YMYL). Do **not** re-expose condition pages to anonymous users, link to them from public surfaces, or add them to the sitemap until that qualification exists. See `docs/implementation/science/health_recommendations.md`, `docs/implementation/science/pubtator_relations_recommendations.md` |
| `Chemistry` | External chemical-identity resolver for the `Food.Compounds` registry — `Chemistry.Resolver.resolve/2` is the identifier-first entry point (looks up by `(namespace, identifier)`, e.g. a MeSH id; cross-references PubChem CID/ChEBI/CAS/InChIKey; writes normalized `compound_identifiers` rows). `import_compound/2` (name→CID via PubChem) is the name-only fallback. Raw payloads in `pubchem_responses`, provenance in `compound_sources`. See `docs/implementation/science/chemistry.md` |
| `Literature` | Two NCBI adapters over the study registry. **Entrez (PubMed) discovery** — crawls each `FoundementalFoodSpecies` by its curated `scientific_name × (linked compounds ∪ keywords)`, fanning each discovered `ScientificStudy` (PMID-keyed) out to every ingredient curated onto the species via `StudyIngredient` (plus `StudyCompound`); ledger `literature_crawl_attempts` is keyed on `(foundemental_species_id, search_term)`; `entrez_responses`, `LiteratureCrawlWorker`. **PubTator3 extraction** — annotates a `ScientificStudy` into `StudyEntityMention` facts (Chemicals/Species/Diseases), chemicals resolved via `Chemistry.Resolver`; also parses the payload's directional `relations` array into `StudyEntityRelation` rows (chemical↔disease etc.) with both endpoints resolved (chemical→compound, disease→condition), `remine_relations/0` back-fills them from stored payloads; `pubtator_responses`, `pubtator_annotation_attempts`, `PubTatorAnnotationWorker`. Both on the `:imports` queue; discovery/extraction only — never asserts dietary facts (the relations feed the review-gated `Health.RecommendationCandidates`). See `docs/implementation/science/literature_discovery.md`, `docs/implementation/science/pubtator.md` |
| `Onboarding` | Database-driven, admin/nutritionist-editable onboarding questionnaires — one engine (`Onboarding.Question` + embedded `QuestionOption`, `Onboarding.Answer`) over two surfaces. `scope: "user"` questions are admin-authored and **appended as a dynamic step** to the normal-user wizard (`MehungryWeb.Onboarding.FormComponent`; the diet/language/calorie essentials stay typed on `UserProfile`); `scope: "client_default"` is the admin template (seeded from `DietaryHistory.Fields` via `seed_defaults/0`) that `ensure_client_questions/1` **snapshots on first use** into per-nutritionist `scope: "client"` rows the nutritionist owns + edits. Each question is a `value` (text/number) or `single/multi_choice` (EN+EL prompts/options). Answers are `(question_id, subject_type, subject_id)` rows (`"user"` → users.id, `"professional_client"` → professional_clients.id; `prompt_snapshot` for durability). Clients self-fill their nutritionist's set at `/:locale/nutritionist-onboarding/:professional_id` (`ClientOnboardingLive`); user answers surface to the nutritionist on the client file (`ClientDetail` "Onboarding answers" panel). Admin UI `/professional/onboarding-questions/:scope`, nutritionist UI `/nutritionist/onboarding-questions` (shared `OnboardingQuestionLive.{Shared,FormComponent}`). See `docs/features/onboarding_questions.md`, `docs/implementation/entities/onboarding.md` |
| `Inventory` | Shopping baskets and basket items |
| `Plans` | Meal plans and daily meal plans |
| `Posts` | Posts, comments, comment answers, votes |
| `Notifications` | Durable user activity notifications (comment-on-your-recipe, reply, new-follower) for the mobile app. DB is the source of truth (`notifications` table): `Notifications.create/3` (self-notification + unread-follow de-dupe), `list/unread_count/mark_read`. **Emission is triggered in the context**, not the controllers: `Notifications.emit/3` is called from `Posts.create_comment`/`create_comment_answer` and `Accounts.UserContent.save_user_follow`, so **every** client (LiveView + REST + channel) fires one. `emit/3` persists then hands off to a dispatcher seam (`:notification_dispatcher`): `NoopDispatcher` by default (core stays web-free), `MehungryWeb.Api.NotificationDispatcher` in the running app, which delivers the **same** §4 payload to the live `user:<id>` channel, the durable REST inbox (`/api/v1/me/notifications`), and a **presence-gated** Expo OS push (`user_devices` table, `MehungryWeb.Api.PushDispatch` → `ObanWorkers.PushNotificationWorker` on `:mailers`, Expo client behind `:expo_push_client`; skipped when the recipient has a live socket). See `docs/implementation/notifications_system.md` + mobile spec §5.1/§13 |
| `Search` | Full-text recipe search |
| `Survey` | User dietary preference surveys |
| `Languages` | Multi-language translations for ingredients and units. App-wide localization (locale-prefixed URLs `/en/…`·`/el/…`, `MehungryWeb.Locale` + `SetLocale` plug + `RestoreLocale` on_mount, Gettext UI strings, hreflang/canonical) is in **`docs/implementation/localization.md`** |
| `Meta` | Anonymous, consent-independent, zero-PII traffic metrics — a daily `daily_session_metrics` counter (count + total duration) written by `Meta.SessionAggregator` when a LiveView process dies (`MehungryWeb.SessionMetrics` on_mount, no consent gate). This is the honest denominator GA4 can't give (GA only counts consented users). All GA4-duplicating server-side analytics (per-visit `visits` table, referrer/traffic-source/device/session-journey reconstruction, SEO referrer reports, geo enrichment) were **removed** in favour of GA4 + Search Console; the only admin surface left is a slim `/professional/analytics` showing the session counter + real-time Presence "online now" |
| `BetaSignups` | Android closed-testing tester list. Public shareable signup page at `/trial` (`MehungryWeb.TrialLive.Index`, landing layout, Turnstile-guarded) stores emails in `beta_signups` (canonical-email dedupe + per-row `unsubscribe_token` + a `platforms` array — Android/iOS/Web — the tester picks on signup, defaulting to all); signup sends a branded welcome email (`Accounts.deliver_trial_welcome/2`). Self-service removal via an on-page box **or** the one-click token link `/trial/unsubscribe/:token`. Admins view/delete the list and bulk-load it into the invite sender at `/professional/android-beta` (`AndroidBetaLive`), which sends the opt-in invite (`Accounts.deliver_android_beta_invite/2`) to typed recipients or the `:android_beta` Google Group (`ANDROID_BETA_OPT_IN_URL`/`ANDROID_BETA_GROUP_EMAIL`). **Per-version send tracking**: each delivered invite records a `beta_invite_sends` row keyed on `(canonical_email, version)` (idempotent per build; `BetaSignups.record_send/3`); the admin sets the "Version being sent" (`ANDROID_BETA_CURRENT_VERSION` default), the tester list shows each tester's received versions + platform badges, and the bulk-load buttons (**"Load Android testers"**, **"Load testers missing <version>"** via `BetaSignups.signups_missing_version/2`) are scoped to Android-interested testers so iOS/Web-only signups aren't emailed the Android invite |
| `History` | User activity history |
| `Professionals` | Nutritionist profiles, client invitations, assignments, appointments, meal plan ratings, and public **scientific Articles** (draft→published, per-paragraph images + references to PubMed studies / food species / compounds / diseases; `/nutritionists/:slug/articles/:article_slug`). Public SEO-indexed profiles + directory (`/nutritionists`, `/nutritionists/:slug`) with weekly-availability booking (request → nutritionist accept → email + `.ics` invite) and Stripe Connect payout onboarding. Also **client records / dietary history** (`ProfessionalClient` + `ClientIntake` + `ConsultationNote` + `ClientCondition`) — a nutritionist-owned "patient file" holding PII directly, **always linked to a platform `User` (`user_id` required — never headless)**; created by CSV import (`DietaryHistory.{CsvParser,Importer}`, which requires a `:user_id`) **or** by hand in `ClientRecordEditor` (reached from a client — the roster, record list, and record editor are unified under `/nutritionist/clients`; there is no separate records roster or user picker). A record can be linked to several **existing** `Health.Condition`s via the `professional_client_conditions` join (`ClientCondition`, `many_to_many :conditions`; `add_client_condition/2`·`remove_client_condition/2`·`list_client_conditions/1`) — the structured client↔condition link, recorded **nutritionist-only** in the editor (existing conditions only; never creates one), which unblocks surfacing research notes against a client's conditions. Also **per-nutritionist research notes** (`ResearchNote` + `ResearchNotes` context, `research_notes` table) — the saved suggestions + custom notes captured from the research search (`/nutritionist/research/notes`, "My notes"); private per user — see `docs/features/professionals/research_notes.md`. See `docs/features/professionals/professional_profiles.md`, `docs/features/professionals/appointments_booking.md`, `docs/features/professionals/articles.md`, `docs/features/professionals/client_records.md`, `docs/implementation/professionals/payments/nutritionist_payments_stripe_connect.md`, `docs/implementation/professionals/integrations/google_meet.md` |
| `Subscriptions` | Subscription tiers, Stripe integration, AI feature quota enforcement — see `docs/features/subscriptions_billing.md` |
| `AI.Bot` | Managed social media recipe pipeline — monthly configs, review queue, translations, post logs |
| `Billing` | Stripe checkout sessions and webhook handling (`Billing.StripeHandler`) — see `docs/features/subscriptions_billing.md` |
| `Social` | Social platform layer (`social/`): `Social.Publisher` fan-out (behind `Social.PublisherBehaviour`), `Social.{Facebook, Pinterest}` HTTP clients, and the `Social.Instagram` context — see `docs/growth/social_publishing.md` |
| `FoodData` | External food-data sources (`food_data/`): `FoodData.Usda.{SearchClient, FdcClient, FoodParser, SeedFileParser}`, `FoodData.OpenFoodFacts.*`. **Recipe importers** map an external recipe into a `Recipe` via one shared, source-agnostic matching engine — `FoodData.RecipeIngredientResolver` (takes normalized `%{name, quantity, unit, original, metric_grams}` ingredient maps → `{recipe_ingredients, unmatched}`, resolving each against existing ingredients/units/USDA portions; never creates ingredients). `FoodData.SpoonacularImporter` is one adapter over it, but is **shadowed** — its import UI on `/create_recipe` is gated off (`CreateRecipeLive.Index.spoonacular_enabled?/0`, defaults `false`) and its LiveView handlers are inert, so it is not surfaced to any user; the code is kept for reference/re-enablement only. `FoodData.MyPlateImporter` is a second: it imports the **public-domain USDA MyPlate Kitchen** collection (~1,100 recipes) from the **Internet Archive** (Wayback Machine) captures of the original `myplate.gov` pages (`FoodData.MyPlate.{Client, ClientBehaviour}`, `:myplate_client` seam) — deliberately **not** the live `myplate.food` API, which caps full recipes at 100/day/IP and forbids catalog replication (an API term, separate from the public-domain content). Slugs ship as a bundled `priv/myplate/slugs.json` manifest (just identifiers; CDX-API fallback via `Client.cdx_slugs/0`); each recipe is fetched from the closest pre-retirement capture (`web.archive.org/web/{ts}id_/…`), its metadata read from the page's schema.org Recipe JSON-LD and its **ingredients/directions parsed from the Drupal HTML with Floki** (the JSON-LD omits them). Each free-text ingredient line is parsed by `FoodData.MyPlate.IngredientParser` before resolving; `build_recipe_attrs/2` seeds each matched ingredient's `unit_selection` so the review form's unit dropdown shows the resolved choice. Public-domain reuse is credited: `contributor`→`author`, `source_url`→`original_url` (shown as a "Source" link on the recipe Steps tab). MyPlate's own nutrition table is discarded — `create_recipe` recomputes nutrients from matched ingredients. Import is **human-in-the-loop**: an **admin-only** LiveView (`MehungryWeb.ProfessionalLive.MyPlateReview` at `/professional/myplate-review`, admin-gated under the `:default2` session; linked from `/professional/recipes`) opens on a **fuzzy-searchable list of the whole slug corpus** (shared `MehungryWeb.ProfessionalLive.ImportReviewSearch` ranker — the primary way to pick what to import, not a blind "next recipe"), and selecting one loads the matched data into the real `RecipeFormComponent` (editable, unmatched lines listed) beside the raw archived source to compare/fix, with Save (create + advance) and Skip ("pass for now"); a daily-cap/transient fetch failure surfaces as a distinct rate-limited/retry state, never a blank form. Per-slug outcomes persist in `myplate_imports` (`FoodData.MyPlate.{ImportRecord, Imports}`, `completed`/`skipped`) so review resumes across sessions. Every saved import is marked with `recipes.source = "myplate"` (nil for in-app recipes) so the batch can be group-managed — `Food.{count_recipes_by_source, recipe_ids_by_source, delete_recipes_by_source}/1`, surfaced as a "Delete MyPlate imports (N)" admin action on `/professional/recipes`. See `docs/implementation/food/myplate_import.md`. `FoodData.GutenbergImporter` is a third adapter over the same resolver: it imports **public-domain, English-language cookbooks from Project Gutenberg** (a curated `FoodData.Gutenberg.Catalog` of validated titles, currently 3 Italian books ≈ 400 recipes). Because the source is an **unstructured book** (not a per-recipe API), a `FoodData.Gutenberg.Client` (behind `ClientBehaviour`, `:gutenberg_client` seam) downloads the whole plain-text ebook (day-cached) and `FoodData.Gutenberg.BookParser` splits it into recipe blocks per the catalogue's `:format` (`:numbered` — lone-number-delimited prose, usually no ingredient list; `:heading` — ALL-CAPS-title-delimited with an indented ingredient list); extraction is best-effort because the review is human-in-the-loop. `build_recipe_attrs/3` reuses the generic `FoodData.MyPlate.IngredientParser` + resolver; ingredient lists are often empty (the admin adds them by hand). Credit: book title+author→`author`, Gutenberg landing page→`original_url`. The admin review LiveView `MehungryWeb.ProfessionalLive.GutenbergReview` (`/professional/gutenberg-review[/:book_id[/:index]]`, `:default2`) has a book picker → a fuzzy-searchable recipe list per book (shared `ImportReviewSearch` ranker) → the same `RecipeFormComponent` beside the verbatim book excerpt. The unit of work is a recipe **ref** `"<book_id>:<index>"`; outcomes persist in `gutenberg_imports` (`FoodData.Gutenberg.{ImportRecord, Imports}`). Imports are **staged `private: true`** (per-recipe "Publish on save" toggle, default private) so an ingredient-matching sweep doesn't dump half-curated recipes into public browse; because the shared `RecipeFormComponent` doesn't submit `private`/`source`/`author`/`original_url`, the review LiveView **re-injects** them at save (else `create_recipe/1`, which builds its changeset purely from form params, would persist them public + untagged). Saved imports carry `recipes.source = "gutenberg"` (same group-management + "Delete Gutenberg imports (N)" action). See `docs/implementation/food/gutenberg_import.md`. `FoodData.UniToolsImporter` is a **fourth** adapter over the same resolver: it imports the **UniTools World Recipes** dataset (501 recipes/127 countries, bilingual ru/en → en only) from a **bundled** `priv/unitools/unitools-recipes-v1.json` file (`FoodData.UniTools.{Client, ClientBehaviour}`, `:unitools_client` seam, day-cached). Unlike the other sources UniTools ingredients are **already structured** (`%{name, quantity, unit, note}`), so `FoodData.UniTools.Decoder` builds the resolver's normalized input maps **directly** (no `IngredientParser` text round-trip); it also maps `country`→`cousine` (via the wrapper's `countries` list) and reads licence/attribution/landing from the file's own wrapper (not hardcoded). **The key difference: UniTools is CC BY-SA 4.0, not public domain** — so each saved recipe is stamped with a dedicated **`recipes.license`** column (`"CC BY-SA 4.0"`, rendered as a visible "Licensed under …" notice next to the Steps-tab Source credit in `recipe_source/1`) to satisfy ShareAlike; `author`/`original_url`/`license`/`source`/`private` are **re-injected** at save like Gutenberg (the shared form doesn't submit them). **Photos are NOT imported** (per-image Wikimedia Commons licences vary wildly — image_url left nil for cover-generation). Admin review LiveView `MehungryWeb.ProfessionalLive.UniToolsReview` (`/professional/unitools-review[/:dataset_id[/:index]]`, `:default2`) mirrors Gutenberg (dataset picker → fuzzy-searchable recipe list → `RecipeFormComponent` beside the verbatim dataset JSON); unit of work is ref `"<dataset_id>:<index>"`, outcomes persist in `unitools_imports` (`FoodData.UniTools.{ImportRecord, Imports}`), staged `private: true`, `recipes.source = "unitools"` (same group-management + "Delete UniTools imports (N)" action). See `docs/implementation/food/unitools_import.md`. (**Note:** the Spoonacular importer persists full recipes, which likely violates Spoonacular's TOS — which is why it is now shadowed; MyPlate, Gutenberg, and UniTools are the sanctioned paths) |
| `Storage` | Object-storage facade (`storage.ex`) for all image/media, backed by **Supabase Storage** (REST). **Use `Mehungry.Storage` for all image/media.** See `docs/implementation/infrastructure/object_storage.md`. (`Mehungry.S3` survives only as the low-level wrapper for the USDA seed-file *import source* — a separate data bucket, not app object storage) |

**Facade convention:** `Mehungry.Food`, `Mehungry.Accounts`, and
`Mehungry.Users` are permanent defdelegate facades — public functions never
break when internals move. New code may call sub-modules directly; when adding
a public function to a sub-module, add a matching `defdelegate` to the facade.
Architecture overview: **`docs/implementation/infrastructure/architecture.md`**.

**Reference architectures** (`docs/reference_architecture/`) — reusable design
patterns to follow when building new features of the same shape. Currently:
**`oban_ui_connected_worker.md`** — the "kick off a large Oban job fan-out from a
LiveView, then watch it finish live" pattern (durable per-unit tracking rows as
source of truth, dedicated queue, two-tier PubSub broadcast + flush-timer
coalescing, stream-based O(1) row patches), distilled from the S3 → USDA
ingredient-seeding flow.

**Cachex** runs two named caches started in `Mehungry.Application`:
- `:recipes_cache` — LRU, limit 150
- `:cache_user_tokens`

### AI Subsystem (`apps/mehungry/lib/mehungry/ai/`)

Overview of how AI is used across the product (capabilities, providers, internal
collaborators, cross-cutting principles): **`docs/implementation/ai/ai.md`** — the front door to
the `docs/implementation/ai/` folder.

A custom Anthropic API layer — do not use raw HTTPoison calls for AI work:

- `AI.Client` — shared HTTP client for the Anthropic Messages API. Handles auth, retries (exponential backoff on 529 rate-limit and timeouts), and response parsing. Default model: `claude-haiku-4-5-20251001`, default max_tokens: 2048.
- `AI.Agent` — generic tool-use loop. Runs a conversation until `end_turn` or `max_iterations` (default 10). Accepts a `handler` function `fn(tool_name, input, acc) -> {result, new_acc}` — the `context` arg is a threaded **accumulator** (result fed back to the model, `new_acc` carried on), and `run/6` returns `{:ok, text, final_acc}` so handlers hand real state (validated output, provenance sets) back to the caller without a process dictionary. Emits `[:mehungry, :ai, :agent, :run|:tool, …]` telemetry (tagged per `agent`) aggregated by `MehungryWeb.PromEx.AiPlugin` — see `docs/implementation/infrastructure/observability.md`.
- `AI.Agents.RecipeAgent`, `MealPlanAgent`, `NutritionistAgent` — domain-specific agents built on `AI.Agent`.
- `AI.ImageGenerator`, `AI.IngredientTranslator`, `AI.RecipeTranslator`, `AI.MealPlanGenerator` — standalone AI utilities.
- `AI.RecipeInsight` + `AI.InsightCaptioner` — the **recipe insight social-graphic** feature: compose a shareable card from a recipe's real photo + a *deterministic* macro-donut/badge overlay (truthful data, drawn with `:image`/vix by the web-side `MehungryWeb.InsightGraphic`), where AI only selects the standout characteristic + writes the headline/caption. Orchestrated by `MehungryWeb.RecipeSocialGraphicWorker` (`:ai_agents` queue) → `Mehungry.Storage` → `Food.RecipeSocialGraphic`. Quota key `"graphic_generation"`. Admin action on `/professional/recipes`, per-user button on `RecipeDetailsComponent`. See `docs/implementation/ai/recipe_insight_graphics.md`.

**Bumblebee/EXLA is gone from the deployed apps.** The local extractive-QA model for measurement extraction now lives in a separate, **non-deployed** umbrella app, `apps/mehungry_local_ai` (`MehungryLocalAi.{QA, PMC, Extractor, Client}` + `mix local_ai.extract`), which runs on a GPU box and talks to the server only over the token-guarded `/api/local_ai/*` REST API — it does PMC fetch + parse + QA extraction locally and posts full text + candidates back. It's excluded from the release and the Docker build, so `nx`/`exla`/`bumblebee`/`xla` are never fetched or compiled in production. See `docs/implementation/ai/measurement_extraction.md`. (`AI.EmbeddingServer` was dead code and was removed; the surviving recipe-embedding path uses the OpenAI API + pgvector, no Nx.)

Config key: `:anthropic_api_key` (read from `ANTHROPIC_API_KEY` env var in `runtime.exs`).

### AI Bot Pipeline (`apps/mehungry/lib/mehungry/ai/bot/`)

Automated recipe-to-social-media pipeline:

1. `AiBotConfig` — monthly config with theme, bot user, and `publish_times` map (meal_type → language → UTC time string).
2. `WeekConfig` / `DayConfig` — optional sub-configs to override week/day themes.
3. `AiBotRecipe` — tracks each generated recipe with status: `pending_review → approved/rejected → published`.
4. Oban cron fires `DailyRecipeGenerationWorker` at **2am UTC daily** → generates one recipe per meal type via `RecipeAgent` → schedules `RecipePublishWorker` jobs (one per meal × language) at the times in `publish_times`.
5. Admin reviews at `/professional/ai-bot/review` before publish jobs run.
6. `RecipePublishWorker` calls `Mehungry.Social.Publisher.publish_recipe/5` (mockable via app config key `:social_media_publisher`) — see `docs/growth/social_publishing.md`.
7. `AI.Bot.Notifier` sends admin email when batch is ready for review.

**Personas / Setups / Orders (authentic voice)** — recipes can be authored in the voice of a reusable **`AI.Bot.Persona`** (grandma, tavern, dietologist…), bound to a cuisine/place/story/condition/seed-ingredients by a named **`AI.Bot.RecipeSetup`**. **Cuisine is the top generation constraint** (`Bot.setup_cuisine/1`, explicit or derived from `origin`): it leads the prompt, forces "commit to one real named dish first" (no external recipe DB — see `docs/implementation/ai/ai_bot_personas.md` §Why not TheMealDB), and styles the cover image per cuisine via the recipe's `cousine` column. A config (and per-`WeekConfig`/`DayConfig` override, cascading day→week→config) references a setup; `Bot.build_brief/1` threads persona + origin + story + seed ingredients (roles: primary/garnish/spice/avoid) into `RecipeAgent.run/2`, which speaks in the persona's voice through both the generation prompt **and** the final polish (hashtags only if `persona.uses_hashtags`). **`AI.Bot.RecipeOrder`** + `RecipeOrderWorker` generate N recipes for a setup on demand into the review queue (no calendar coupling; order rows carry `bot_config_id: nil` + `recipe_order_id`). Admin UI: `/professional/ai-bot/{personas,setups,orders}`. See **`docs/implementation/ai/ai_bot_personas.md`**.

### Subscription Tiers (`Mehungry.Subscriptions`)

Three tiers enforced via `check_quota/2` and `record_usage/2`:
- `"free"` — 0 recipe generations / 0 meal plans per month
- `"m3hungry_plus"` — 15 / 4 per month (consumer premium, billed via Stripe)
- `"pro"` — 30 / 10 per month (nutritionist tier, billed via Stripe)

The owner email (`nikolisgal@gmail.com`) bypasses all quota checks. Use `Subscriptions.pro?/1` and `Subscriptions.nutritionist?/1` for gate checks.

Stripe events are handled via `POST /webhooks/stripe` → `StripeWebhookController` → `Billing.StripeHandler`.

### Oban Queues

```
default:             5 concurrent  — ingredient translation, recipe publishing
ai_agents:           1 concurrent  — recipe generation, translation, image generation, nutritionist agent
mailers:             3 concurrent  — appointment emails/ICS (AppointmentMailerWorker), Expo push (PushNotificationWorker)
imports:             1 concurrent  — condition-seeded literature crawl + admin bulk research ingestion (ResearchIngestionWorker); dormant: species crawl / PubTator / candidate derivation
seed_imports:        1 concurrent  — USDA S3 seed-file imports (SeedFileImportWorker) only
hashtag_reconcile:   1 concurrent  — admin hashtag reconciliation sweep (HashtagReconciliationWorker), one job per recipe
portion_generation:  1 concurrent  — admin derived-portion generation sweep (IngredientPortionGenerationWorker), one job per ingredient
```

Total concurrency is capped at **13 job slots** so background jobs fit within the DB pool (`POOL_SIZE` 18 in prod) with headroom for web/LiveView/Presence — this closes the connection-pool starvation confirmed in prod (`queue_time` spiking to ~10s). See `docs/implementation/infrastructure/oban_production_diagnostics.md`.

`IngredientPortionGenerationWorker` runs the admin-triggered "Generate derived portions" sweep from `/professional/measurement_units` (one durable `ingredient_portion_generation_runs` row per batch, live progress via PubSub — the Oban-UI-connected pattern). It calls `Food.generate_portions_for_ingredient/1`, which idempotently materializes metric + common-recipe portions: mass units (`kg`) from an ingredient-independent constant and volume units (`ml`/`l`/`tsp`/`tbsp`/`cup`) from the ingredient's density (derived from any one existing volume portion). Conversion constants + the density anchor live in `Mehungry.Food.PortionConversion` (shared with the `ReconcileRecipeIngredientPortions` sweep).

`HashtagReconciliationWorker` runs the admin-triggered "Reconcile hashtags" sweep from `/professional/recipes` (one durable `hashtag_reconciliations` row per recipe, live progress via PubSub — the Oban-UI-connected pattern). It calls `Food.ensure_recipe_hashtags/1`, the shared additive routine that also runs on every recipe create/update. See `docs/growth/hashtags.md`.

`SeedFileImportWorker` is deliberately on its own `seed_imports` queue so a bulk "Load ingredients" run over a full bucket can't starve behind the long-running, self-resuming science pipeline that shares `:imports`. `SeedFiles.reset/2` cancels in-flight jobs by that queue name.

`ResearchIngestionWorker` runs the admin-triggered **bulk research ingestion** from `/professional/health` ("Research ingestion" card) — the production control for `mix research.ingest`. It **fans out one job per condition** (the Oban-UI-connected pattern): each job sends its condition's crawled studies to the `mehungry_extractor` `/analyze` and stores claims + full-text `sections` via the shared `Literature.ResearchIngestion.analyze_condition/2` (reused by the mix task). Per-condition jobs make it **restart-safe** — a reboot only interrupts the in-flight condition (rescued + retried by Oban `Lifeline`, `max_attempts: 3`), while the rest are independent `available` jobs that resume on boot. Progress is tracked on a durable `research_ingestion_runs` row (atomic counter increments) broadcast over PubSub; the run finalizes when `conditions_done + conditions_failed == conditions_total` — as `failed` (red) when **every** condition failed (extractor down the whole run), else `completed`. "Run ingestion" does a **pre-flight reachability probe** (`Mehungry.Extractor.reachable?/0`, a short GET to the configured base URL) and refuses to start with a flash if the extractor link is dead, instead of churning retries. `Literature.enqueue_research_ingestion/1` allows only one run at a time; `cancel_research_ingestion/0` (UI "Cancel" button) cancels its jobs + fails the run, and `reconcile_research_ingestion/0` (called on mount) unwedges a run left `processing` by a crash with no live jobs. The extractor is needed **only** during the run — the nutritionist research search reads purely from the DB afterward.

Full-text (PMC) + measurement extraction moved off-box to the non-deployed `apps/mehungry_local_ai` service over an `/api/local_ai/*` seam. **Decommissioned 2026-10-26 (research-search reshape, Phase 1):** that entire inbound seam (controllers, routes, `:local_ai_api` pipeline) and the `/professional/{science,compound-candidates}` admin UIs were **removed**; `apps/mehungry_local_ai` is now orphaned. The underlying contexts/schemas/tables remain **dormant (not dropped)**. See `docs/features/professionals/research_search.md` and `docs/implementation/ai/measurement_extraction.md`.

Cron: `InstagramTokenRefreshWorker` at `30 1 * * *`, `PinterestTokenRefreshWorker` at `45 1 * * *` (refreshes Pinterest access tokens from the stored refresh token; the Pinterest client also refresh-retries once on a 401), `DailyRecipeGenerationWorker` at `0 2 * * *`, `PipelineWatchdogWorker` every 10 min (resumes any science-pipeline run whose single-threaded chain broke — see `Mehungry.Science.PipelineWatchdog` + `docs/implementation/science/scientific_pipeline.md`).

### Instagram Integration (`Mehungry.Social.Instagram`)

Core-app context for the Instagram Graph API: `Social.Instagram.Token` (token map lifecycle/status), `Social.Instagram.Caption` (2200-char capped captions), `Social.Instagram.Client` behind `Social.Instagram.ClientBehaviour` (stubbed in tests via `:instagram_client` config key). Long-lived tokens are refreshed daily by `InstagramTokenRefreshWorker`; invalid tokens are marked stale and surface as "reconnect" in `/professional/ai-bot/social`. `RecipePublishWorker` publish failures return `{:error, _}` for Oban retries, skipping platforms that already have an `"ok"` post log (manual re-publish passes `force: true`). The publisher seam is typed by `Mehungry.Social.PublisherBehaviour` (`:social_media_publisher` config key).

### Observability

Overview: **`docs/implementation/infrastructure/observability.md`**. The bespoke DIY-observability layer (persistent `telemetry_snapshots` via `MetricsBuffer`, DIY `ErrorTracker` → `error_events`, `query_time_profiles`, custom LiveDashboard pages, process watchdog, custom VM/pool gauges) was **removed** — this is now a clean, standard baseline to build fresh on.

What remains is stock Phoenix telemetry, split by surface. **LiveDashboard** at `/dashboard` (admin-gated via `config :mehungry, :admin_email` + `MehungryWeb.Plugs.RequireAdmin`) renders `MehungryWeb.Telemetry.metrics/0` (standard Phoenix/Ecto/Oban/VM metrics) as live charts. The **Prometheus scrape** is owned by **PromEx** (`MehungryWeb.PromEx`, a `use PromEx` module in the supervision tree with the standard Beam/Application/Phoenix/PhoenixLiveView/Ecto/Oban plugins; Grafana upload + PromEx's own HTTP server disabled): `GET /metrics` is token-guarded by `MehungryWeb.Plugs.RequireMetricsToken` / `:metrics_api_token`, served by `MehungryWeb.MetricsController` via `PromEx.get_metrics/1` (metric names are `mehungry_web_prom_ex_*`-prefixed). **BeamScope** (`/beam_scope` dashboard + token-guarded `/beam_scope/metrics` scrape) and **Oban Web** (`/oban`, job queues UI) are also mounted, admin-gated like `/dashboard`. Prod Oban diagnostics, the broken `remote`/`rpc` console (use `eval`), and the batch-translation backlog are in `docs/implementation/infrastructure/oban_production_diagnostics.md`.

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

**Mobile REST API (`/api/v1`, `MehungryWeb.Api.V1.*`)** — the JSON surface for the React Native client (routes in `router.ex`, serializers in `controllers/api/v1/*_json.ex`). **Whenever you add, remove, or change the shape of any `/api/v1` request/response — a route, a controller action, or a `*_json.ex` serializer field — you MUST update `docs/implementation/new_dec_specs/mobile_api_spec.md` in the same change** so the spec and the implementation never drift. The spec is the contract the mobile client is built against.

**REST ↔ LiveView parity (reuse, never duplicate):** Almost every REST concept already exists as a LiveView concept — the web app shipped first, so the calendar, basket, feed, recipe, nutrition, etc. are all implemented for LiveView already. When building a `/api/v1` endpoint, **find the equivalent LiveView and reuse the exact same domain function it calls** (push the shared logic down into the core `apps/mehungry` context if it still lives in a LiveView module, then call it from both). Do **not** re-derive or copy a transform/calculation into the controller — divergent copies silently drift and produce wrong results (e.g. a daily-nutrition total that no longer matches the calendar). The REST layer should only translate HTTP ⇄ domain calls + serialize; the computation itself must be the one shared function. Only duplicate when reuse is genuinely impossible, and say why.

### Frontend

- **Tailwind CSS** + **DaisyUI** for styling
- **Alpine.js** for client-side interactivity
- **jQuery** + **Select2/Selectize** — legacy select components (being phased out)
- **Vega-Lite** for charts via `Hooks.VegaLite` and `Hooks.ResponsiveChart` JS hooks
- **esbuild** bundles JS; `mix assets.build` / `mix assets.deploy` compile assets

Client hooks: `apps/mehungry_web/assets/js/hooks.js`. Navigation active-state handled by a JS `Proxy` intercepting URL changes (`navigation.js`).

**Google Analytics (GA4)**: Consent Mode v2-gated `gtag.js` in `head.html.heex`, manual `page_view` tracking for LiveView SPA navigation, and a `MehungryWeb.GoogleAnalytics.track/3` seam for custom events — see **`docs/implementation/infrastructure/google_analytics.md`**.

**Design system**: warm-charcoal/paprika/basil token set (`ink`, `paprika`, `basil`, `parchment` in `tailwind.config.js`) rolled out to `/profile` only so far — palette rationale, component rules, and the CSS-variable pattern for retheming shared components (e.g. `SelectComponent`) without breaking their other call sites are in **`docs/implementation/infrastructure/design_system.md`**.

### Modal Approaches

Three coexisting patterns — prefer option 3 for new code:
1. CSS + `Phoenix.LiveView.JS` — recipe browser
2. CSS + client Hooks — elsewhere
3. `core_components.ex` modal — **preferred for new code**

## Testing Layers

1. **Unit** — `ExUnit` in `apps/mehungry/test/`
2. **Integration/smoke** — `ExUnit` with `ConnCase`/`LiveViewTest` in `apps/mehungry_web/test/`
3. **Functional** — Wallaby (browser-driven) in `apps/mehungry_web/test/features/`

Wallaby tests require a `chromedriver` binary on `PATH` (no longer vendored in the repo — see `docs/implementation/infrastructure/operations.md`).

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
- `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_STORAGE_BUCKET` — object storage for all images/media via the `Mehungry.Storage` facade; see **`docs/implementation/infrastructure/object_storage.md`**
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ASSETS_BUCKET_NAME` — **only** for the USDA seed-file *import source* bucket (`Mehungry.S3`), not app object storage
- `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `INSTAGRAM_CLIENT_ID`, `INSTAGRAM_CLIENT_SECRET`
- `PINTEREST_CLIENT_ID`, `PINTEREST_CLIENT_SECRET`; `PINTEREST_ENV` selects the API environment — `live` for the real API, anything else (or unset) for the sandbox
- `FDC_API_KEY` — required for USDA food lookups (basket search + AI ingredient creation); there is no fallback key
- `SPOONACULAR_API_KEY` — optional; the shared paid key behind the "Import from Spoonacular" flow on `/create_recipe` (`FoodData.SpoonacularImporter`). When unset the import UI fails fast with a friendly message instead of a 401; per-user rate-limited (20 req/min)
- `OPENAI_API_KEY` — optional (embeddings, cover images)
- `TURNSTILE_SITE_KEY`, `TURNSTILE_SECRET_KEY` — Cloudflare Turnstile CAPTCHA on registration (optional; verification is skipped when the secret key is unset)

## Deployment Notes

- Production runs on Fly.io; the canonical host is `www.m3hungry.com` (the apex `m3hungry.com` has no TLS cert — point clients at `www`).
- **Topology (`fly.toml`):** 2 `shared-cpu-1x`/1GB machines in `lhr` (`min_machines_running = 2`) for single-machine-failure redundancy, each with a 512MB swap cushion (`swap_size_mb`, must be a top-level key or TOML folds it into the preceding table). Deploys are **rolling** (`strategy = "rolling"`) and gated on the `GET /health` liveness probe (`[[http_service.checks]]` → `MehungryWeb.HealthController`, a pure 200 "ok"), so deploys are zero-downtime and a hung BEAM is auto-restarted. The `[deploy] release_command` runs migrations in a one-off machine before the new release goes live.
- **DB connections:** app connects via the Supabase **session pooler** (`…pooler.supabase.com:5432`); `POOL_SIZE = 10` per machine, so 2 machines + migrator ≈ 22 pooled clients. The Supavisor **Pool Size is set to 25** in the Supabase dashboard (raise it there before scaling machines up, or the extra connections hit the cap — Postgres `max_connections` is 60). *(Was single-machine + `immediate` deploys while the pooler was capped at 15.)*
- The migrator app (`migrator/`) runs DB migrations as a separate step.
