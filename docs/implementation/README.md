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
- [`translation_gates.md`](translation_gates.md) — translation gating rules.
- [`app_status.md`](app_status.md) — status snapshot (DB/GA4/GSC/social).
- [`overview_doc_template.md`](overview_doc_template.md) — template for new overview docs.
