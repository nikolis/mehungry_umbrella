# Implementation

How the features ([`../features/`](../features/)) and growth work
([`../growth/`](../growth/)) are actually built — schemas, contexts, pipelines,
workers, infra — and their state. Reusable patterns abstracted from here live in
[`../reference_architecture/`](../reference_architecture/).

Domain clusters (each with its own front-door index):

- [`science/`](science/science.md) — chemistry → literature → compound layers → health-advice pipeline.
- [`food/`](food/food.md) — recipes, ingredients, nutrients, importers, nutrition calculation.
- [`ai/`](ai/ai.md) — AI client/agents, bot pipeline, personas, measurement extraction, insight graphics.
- [`entities/`](entities/entities.md) — canonical schema data dictionary for fundamental entities.
- [`infrastructure/`](infrastructure/architecture.md) — architecture, observability, security, operations, object storage, scaling, Oban diagnostics.
- [`professionals/`](professionals/) — professional-feature **mechanics**: payments (Stripe Connect), Google Meet integration, implementation status.
- [`new_dec_specs/`](new_dec_specs/mobile_api_spec.md) — **mobile REST API contract** (keep in sync with `/api/v1` code) + React Native app prompt.
- [`users/`](users/accounts.md) — Accounts context internals.
- `legal/` — legal review notes.

Cross-cutting / non-functional docs:

- [`localization.md`](localization.md) — locale-prefixed URLs, Gettext, translation flow.
- [`notifications_system.md`](notifications_system.md) — durable notifications + dispatch seam.
- [`history_calendar.md`](history_calendar.md) — the weekly meal calendar / self-tracker (`History` context + denormalized per-day nutrition).
- [`posts_feed.md`](posts_feed.md) — the `Post` model, home feed, comments/answers, and votes (`Posts` context).
- [`published_plans.md`](published_plans.md) — public SEO-indexed meal-plan snapshots + week share card/post (`PublishedPlans`).
- [`inventory_basket.md`](inventory_basket.md) — shopping baskets, recipe/meal import, and the week-list flow (`Inventory`).
- [`plans_vocabulary.md`](plans_vocabulary.md) — disambiguates the four "plan" contexts (`History` / `MealBlueprints` / `PublishedPlans` / legacy `Plans`).
- [`translation_gates.md`](translation_gates.md) — translation gating rules.
- [`app_status.md`](app_status.md) — status snapshot (DB/GA4/GSC/social).
- [`architecture_audit_2026-10-27.md`](architecture_audit_2026-10-27.md) — whole-system doc-coverage + architecture audit (gaps, drift, risks).
- [`overview_doc_template.md`](overview_doc_template.md) — template for new overview docs.
