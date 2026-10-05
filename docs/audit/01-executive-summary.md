# 01 — Executive Summary

*Audit date 2026-10-05. Read with the [README](README.md) for method and confidence labels.*

## What Mehungry is

Mehungry (m3hungry) is a Phoenix/LiveView **web** application that bundles five distinct products into one:

1. **A deep nutrient tracker** — leads with "Track 168 nutrients per meal", "Backed by USDA FoodData Central".
2. **An AI generator** — AI recipes, AI cover images, and AI weekly meal plans (Anthropic + OpenAI).
3. **A recipe social network** — user recipes, comments, votes, follows, hashtags, in English and Greek.
4. **A health-science engine** — links health conditions → bioactive compounds / nutrients → foods, mined from PubMed/PubTator and USDA.
5. **A nutritionist marketplace + practice SaaS** — SEO public profiles, booking, client records, articles, Stripe Connect payout onboarding.

Pricing (verified in code): **Free** (0 AI generations), **Plus €9.99/mo or €99/yr** (15 recipe / 4 meal-plan generations), **Pro €29.90/mo or €290/yr** (nutritionist tier, 30/10). Operator is presumed EU-based (€ pricing, el/en locales, AWS eu-central-1, gmail owner), bootstrapped, and effectively solo.

## Overall assessment

Mehungry is **technically impressive and unusually broad, but pre-product-market-fit, structurally unfocused, and built well ahead of its legal scaffolding.** The engineering is real: a working AI subsystem, a genuine USDA-backed nutrition layer, a polished landing page, a substantial nutritionist back-office, and an elaborate scientific pipeline. But the breadth is the core problem — each of the five products competes against an entrenched, better-funded, mobile-native incumbent, and the solo founder cannot win five land-grabs at once. There is **no public evidence of traction** (the landing page honestly carries no user counts), and several headline capabilities are thinner than marketed.

The three issues that dominate everything else:

### 1. The marketplace doesn't collect money on the mainline (capability gap)
On master and the current branch, Stripe Connect is onboarding-only — no charge path, no fee, no ledger (verified). A nutritionist can complete KYC to receive payouts the product never collects; bookings are free request-and-accept. The paid-booking flow **was built on an unmerged branch (`new_professional_nutritionist_features`) but never merged**, so any consultation-revenue plan depends on finishing and shipping that branch. This is the single biggest gap between the documented/intended product and the deployed one.

### 2. The health engine is a legal liability, not a safe differentiator (compliance)
Surfacing "for condition X, favour/avoid food Y" to consumers very likely constitutes **unauthorised health claims** under Reg. (EC) 1924/2006 and pushes the software toward **medical-device** qualification under the MDR. The existing "informational only — not medical advice" disclaimers **do not cure** either problem. Combined with special-category (health) data held in nutritionist client records **with no documented Art. 9 basis, no processor contracts disclosed, and an erasure routine that leaves that health PII behind**, the health/marketplace surface is the riskiest part of the product. See [risk register](03-eu-compliance-risk-register.md) R1–R4.

### 3. The positioning is diffuse (market)
The homepage leads with "168 nutrients, USDA-backed" — which is **Cronometer's exact wedge** (Cronometer already tracks 80–95 verified nutrients, has 10M+ users and native mobile apps). Attacking that head-on, web-only, with no budget, is the weakest possible fight. Meanwhile the genuinely novel asset — a pro↔client closed loop plus an EU/Greek-localized nutritionist platform — is buried.

## Strongest opportunities

- **A B2B-first pivot to an EU/Greek independent-dietitian platform.** Here the breadth becomes a feature: the tracker, AI meal plans, recipe library, and science engine become the *client-facing layer* the dietitian hands out, while the dietitian pays for practice tools + lead generation. Willingness-to-pay is proven (Nutrium ~€38–88/mo; Pro €29.90 undercuts it), the channel (direct outreach to a small, defined universe) fits a solo founder, web-only is acceptable for a professional desktop workflow, and **Greek localization is a real moat** against Nutrium/Healthie. This is the recommended direction. See [positioning](06-positioning-strategy.md).
- **The GLP-1 micronutrient tailwind.** Ozempic/Wegovy users eat far less and face micronutrient-deficiency risk, shifting the whole market from calorie-counting toward micronutrient adequacy — favourable to the USDA-exact nutrition wedge, *if* paired with a mobile logging experience.
- **USDA-exact nutrition applied to generated/shared recipes** — few competitors compute real nutrition on AI-generated and community recipes; this is a defensible niche capability.

## Biggest risks

| Risk | Type | Severity |
|------|------|----------|
| Condition→food = unauthorised health claims (Reg. 1924/2006) | Legal | **Critical** |
| Special-category health data with no Art. 9 basis / incomplete erasure / no DPAs | Legal | **Critical** |
| Possible unregistered medical-device (MDR) qualification | Legal | High |
| GA loads before consent; thin privacy policy; no ToS/Impressum; false "never shared" statement | Legal | High |
| No 14-day withdrawal right / VAT transparency on paid subscriptions | Legal | High |
| AI Act Art. 50 (AI-content labelling) deadline ~Aug 2026; Art. 4 literacy already overdue | Legal | High |
| Marketplace collects no payment; booking monetization doesn't exist in code | Product | High |
| Web-only, no native app, in a phone-first daily-logging category | Product/Market | High |
| Free tier = 0 AI generations → the headline feature is paywalled on first use | Product/Growth | High |
| Diffuse positioning across five incumbent-held markets | Market | High |
| Two-sided cold-start on both the social feed and the marketplace | Market | Medium |

## Recommended direction (one sentence)

**Stop competing as a consumer calorie tracker and as a social network; reposition Mehungry as the GDPR-native, Greek-first all-in-one platform for independent EU dietitians — but treat the health-claims/medical-device/health-data exposure (R1–R4) and the missing booking-payment flow as blocking prerequisites before scaling the health and marketplace features.**

The sequencing matters: **fix the Phase-0 legal items and the free-AI/mobile funnel leaks first**, validate dietitian demand and marketplace liquidity with cheap concierge experiments, and only then invest in the marketplace payment rails and native mobile. Do not spend on acquisition until the funnel leaks are closed. See the [prioritized roadmap](08-prioritized-roadmap.md).
