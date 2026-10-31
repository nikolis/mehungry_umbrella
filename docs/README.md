# Docs

Documentation lives in four top-level folders, split by **what kind of thing** each
doc is about:

| Folder | Holds | The question it answers |
|---|---|---|
| [`features/`](features/) | Functional features — the value we deliver to customers (nutritionists + normal users): vision, positioning, personas, and what each feature does for the user | *What do we do for the customer?* |
| [`growth/`](growth/) | Surfacing / go-to-market — work that isn't direct customer value but gets the product found (SEO, hashtags, social publishing + copy, growth plan) | *How do we get the product found?* |
| [`implementation/`](implementation/) | How the features and growth work are actually built, and their state — schemas, contexts, pipelines, workers, infra, API spec, status | *How is it built and operated?* |
| [`reference_architecture/`](reference_architecture/) | Proven, reusable design patterns, source-agnostic | *What shape should a new feature of this kind take?* |

**The axis is per-document.** Each whole doc is filed by its **center of gravity**
(what it is *mostly* about) — docs are not split across folders. So a domain's
feature story lives under `features/`, while its schema/worker mechanics live under
`implementation/` (e.g. the professional-nutritionist *feature* is in
`features/professionals/`; its payments and integration *mechanics* are in
`implementation/professionals/`).

Start with [`features/product_foundation.md`](features/product_foundation.md) — the
source of truth every product decision traces back to.

**Keep docs in sync with code** (see `CLAUDE.md`): a feature/UX change updates the
`features/` doc, a surfacing change updates `growth/`, a schema/worker/infra change
updates the `implementation/` domain doc, and any `/api/v1` change updates
`implementation/new_dec_specs/mobile_api_spec.md` — in the same commit.

> Borderline calls worth knowing: `features/subscriptions_billing.md` keeps the
> tiers/pricing story front-facing though Stripe mechanics are also described there;
> `implementation/localization.md` and `implementation/notifications_system.md` are
> filed by mechanics even though each underpins a user-facing capability.
