# Mehungry — Product, EU-Compliance, Market & Growth Audit

**Audit date:** 2026-10-05 · **Scope:** read-only assessment of the Mehungry Phoenix umbrella at `/home/nikolis/git/mehungry_umbrella` (branch `f/exporting_weekly_proram`). No application code, config, dependencies, or deployment were changed. The only files written are this report set.

This audit is an evidence-based assessment of the product *as it exists in the code today*, its EU legal/regulatory exposure, its market fit and competition, and a recommended positioning + growth path. It is deliberately critical, not promotional. Legal sections are **preliminary risk analysis, not a formal legal opinion** — items requiring a lawyer are flagged.

## How to read this

Start with the **Executive Summary**. Each section below is a standalone file.

| # | File | What it covers |
|---|------|----------------|
| — | [README.md](README.md) | This index + method + limitations |
| 01 | [01-executive-summary.md](01-executive-summary.md) | The product in one page, top opportunities, biggest risks, recommended direction |
| 02 | [02-product-feature-inventory.md](02-product-feature-inventory.md) | Every user-facing feature, implementation status, user journeys, marketing-vs-reality |
| 03 | [03-eu-compliance-risk-register.md](03-eu-compliance-risk-register.md) | 14-item EU risk register (GDPR, health-claims, MDR, AI Act, DSA, consumer law, EAA) + action plan |
| 04 | [04-market-fit.md](04-market-fit.md) | Segments, the real problem, demand evidence vs unknowns, validation experiments |
| 05 | [05-competitive-analysis.md](05-competitive-analysis.md) | Dated competitor profiles + comparison matrix |
| 06 | [06-positioning-strategy.md](06-positioning-strategy.md) | ICP, 3 positioning options + recommendation, messaging |
| 07 | [07-go-to-market.md](07-go-to-market.md) | Ranked channels, funnel fixes, 30/60/90-day plan, metrics |
| 08 | [08-prioritized-roadmap.md](08-prioritized-roadmap.md) | Single ranked roadmap across legal/product/validation/growth |
| 09 | [09-open-questions-and-assumptions.md](09-open-questions-and-assumptions.md) | Material unknowns that change the conclusions |
| 10 | [10-sources-and-evidence.md](10-sources-and-evidence.md) | External citations (dated) + repo path/line index |

## Method

- **Repository trace** of routes (`router.ex`), LiveViews, Ecto contexts/schemas, plugs, and the Stripe/AI integrations. Findings cite `path:line`.
- **Four parallel investigation streams** — product/UX, EU compliance (with live legal research), competitive/market-fit (with live market research), positioning/GTM — reconciled against each other and against direct code re-verification of every high-severity or surprising claim.
- **External research** used dated, cited sources (accessed 2026-10-05) for EU legislation, regulator guidance, competitor pricing, and market data. See file 10.

## Confidence labels used throughout

- **Verified** — read directly in the code or a cited primary/secondary source.
- **Inferred** — deduced from structure, not traced end-to-end.
- **Unverifiable from code** — e.g. how fully a database table is populated, encryption-at-rest, or the operating entity's size — flagged as an open question.

## Three things the reader should not miss

1. **The nutritionist marketplace does not collect payments on the mainline today.** On master and the current branch (`f/exporting_weekly_proram`), Stripe Connect exists only as payout-onboarding ("minimal onboarding slice", `stripe_handler.ex:74`) — **no** `PaymentIntent`, `application_fee`, `transfer_data`, or `professional_payments` ledger (verified by grep). Bookings are free request-and-accept. The paid-booking flow (with an `appointment_payment` schema + `application_fee`) **was built on an unmerged branch, `new_professional_nutritionist_features` (commit `5d91fde5`), but has not been merged into master or the current branch.** `CLAUDE.md`/prior notes describe that unmerged work as if it were live. Any marketplace-revenue plan depends on finishing + merging that branch.
2. **The health/condition→food feature is the single biggest legal exposure**, not a differentiator to lean on as-is. It plausibly makes unauthorised health claims (Reg. 1924/2006) and edges toward medical-device territory (MDR). Disclaimers do not cure either. See risk register R1/R2.
3. **The product is five products in one** (deep nutrient tracker, AI recipe/meal-plan generator, recipe social network, health-science engine, nutritionist marketplace+SaaS). The central strategic recommendation is to **focus** — the audit argues for a B2B-first dietitian-platform positioning, with the rest becoming the client-facing layer.
