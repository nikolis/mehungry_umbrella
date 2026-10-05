# 04 — Market-Fit Assessment

*Grounded in the code (`landing_live.ex`, `CLAUDE.md`) + dated external research (see [file 10](10-sources-and-evidence.md)). No claim of product-market fit is made — the evidence does not support one.*

## The problem(s) Mehungry plausibly solves

1. **"I want exact, trustworthy nutrition, not crowdsourced guesses"** — the Cronometer problem, extended to *recipes* (nutrition pre-computed from USDA-mapped ingredients). This is the strongest, most differentiated value.
2. **"I want recipes / meal plans generated to my targets without manual work"** — the AI-convenience value.
3. **"I'm an EU nutritionist who wants clients *and* a tool where clients already log their food"** — the marketplace + same-app-logging value. Genuinely novel vs back-office-only SaaS, **but today the marketplace collects no payment** (see [feature inventory](02-product-feature-inventory.md) journey c).

## Likely segments

- **Primary (consumer):** detail-oriented, health-literate EU users — GLP-1 micronutrient-watchers, chronic-condition self-managers, macro/micro trackers who find Cronometer utilitarian and MyFitnessPal shallow. Narrow but high-intent, higher willingness-to-pay.
- **Primary (professional):** solo EU dietitians/nutritionists who want low-cost client management **plus lead generation** — Nutrium/NutriAdmin users frustrated those tools don't bring clients.
- **Secondary:** home cooks wanting a recipe social feed with nutrition attached — the **weakest/most crowded** segment (competes with Instagram, Pinterest, Samsung Food).

## Frequency, urgency, willingness-to-pay

- **Tracking + planning** is a daily, habit-driven behaviour with high retention *if sticky* — but stickiness in this category requires a **phone**. Web-only undercuts the core daily-logging loop (barcode/photo logging is a camera behaviour).
- **Professional side** has high urgency + high willingness-to-pay (it's their livelihood). €29.90/mo is competitive vs €25–88 incumbents **if the marketplace delivers real leads** — that "if" is the whole bet, and it currently has no payment rails and a cold-start directory.

## Competing alternatives & "do nothing"

The strongest alternative is **stitching free tools**: Cronometer (free micros) + ChatGPT (free recipe ideas) + Instagram (free social) + Nutrium (pro tooling). Each slice is already covered by a focused product. Switching to Mehungry is only compelling for someone who needs **two or more of these jobs at once** — which is also why it's hard to market (no single clear category).

## Strongest vs weakest value props

- **Strongest:** USDA-exact nutrition on *generated/shared* recipes; a pro↔client closed loop for EU dietitians.
- **Weakest:** the social feed (cold-start, no network effect, competing with giants) and the "scientific" PubTator condition→compound layer (impressive engineering, unproven consumer trust, and — critically — EU **health-claim/medical-device exposure**; see [R1/R2](03-eu-compliance-risk-register.md)).

## Adoption barriers

1. **No native mobile app** — the biggest one; the category is phone-first.
2. **Two-sided cold-start** on both the social feed and the marketplace (needs pros *and* clients; feed value needs creators).
3. **Trust in AI nutrition advice** — hallucinated quantities; plus the regulatory exposure on condition advice.
4. **Crowded, well-funded field** — every axis has a 10M+-user or VC-backed incumbent.
5. **Diffuse positioning** — "tracker + AI chef + social network + marketplace" can't be said in one line.
6. **Free tier ships 0 AI generations** — the single most differentiated feature is invisible until payment (a conversion-killer).

## Core vs distracting features

- **Core:** USDA-exact nutrition + AI recipe/meal-plan to targets + EU nutritionist platform.
- **Likely distracting / un-moated now:** the full social network (votes/follows/hashtags), the AI social-media bot pipeline, and the deep PubMed/PubTator science layer — high build cost, unclear near-term pull, and regulatory exposure.

## Product-market-fit evidence: what's MISSING

There is **no** public user/MAU count, **no** retention/activation data, **no** paid-conversion rate, **no** marketplace liquidity (active pros, completed bookings), and **no** evidence anyone searches for "all-in-one nutrition + marketplace." The landing page's honest, stat-free copy ("10,000+ foods", "example output") *confirms* pre-traction status. **Conclusion: PMF is unproven; do not assume it.**

## Validation experiments (cheap, fast)

Each has a hypothesis, target user, method, success criterion, and decision rule.

### E1 — Wedge-message test ("exact nutrition on recipes")
- **Hypothesis:** "USDA-exact nutrition, not estimates" converts better than "all-in-one platform."
- **User:** EU health-literate trackers (28–45). **Method:** 3–4 paid landing variants (€200–400 ads) → register CTR.
- **Success:** ≥2× CTR on the exactness message; ≥4% visitor→register. **Decision:** if exactness wins, re-focus positioning there; defer social.

### E2 — Mobile-gap smoke test
- **Hypothesis:** lack of a native app is the #1 drop-off for daily logging.
- **Method:** instrument the web funnel; add an "install app?" interstitial; measure demand for mobile + 7-day logging retention on web.
- **Success:** if >40% want mobile AND D7 logging retention <15%, mobile is the binding constraint. **Decision:** ship a PWA before any acquisition spend.

### E3 — Nutritionist marketplace liquidity (concierge)
- **Hypothesis:** EU dietitians will pay €29.90 if it brings ≥1 paying client/month.
- **User:** 15–25 solo EU (ideally Greek) dietitians. **Method:** manually recruit, onboard, hand-drive lead-gen for 60 days.
- **Success:** ≥30% get ≥1 booked consult; ≥50% say they'd keep paying. **Decision:** if liquidity fails, the marketplace is a feature, not a business — reposition Pro as pure tooling vs Nutrium. *(Prerequisite: a working booking-payment flow, which does not exist yet.)*

### E4 — AI willingness-to-pay fake-door
- **Hypothesis:** Plus buyers are driven by AI meal plans, not recipe gen.
- **Method:** two upgrade buttons ("AI recipes" vs "AI weekly plan"); measure click→checkout intent.
- **Success:** one variant ≥2× the other → re-weight quotas/messaging.

### E5 — Condition-science trust + legal screen
- **Hypothesis:** users trust/act on condition→food guidance.
- **Method:** show the condition feature to a cohort; measure engagement + a trust survey; run a parallel health-claims legal screen (R1).
- **Success:** >25% engage AND no regulatory red flag → keep; else de-emphasize.

### E6 — Head-to-head retention vs Cronometer
- **Hypothesis:** Mehungry retains micronutrient-focused users as well as Cronometer.
- **Method:** recruit 50 Cronometer users, 30-day trial, measure D30 logging retention + NPS.
- **Success:** D30 ≥ 60% of Cronometer's benchmark → viable; else fix logging UX/mobile first.

## Market context (dated)

- **Diet & nutrition apps:** ~$5.8–6.9B (2025–26) at ~12–17% CAGR on narrow definitions; $14–17B at ~20%+ on broad "nutrition technology" definitions. Definitions vary wildly; the reliable signal is strong double-digit growth in a crowded category.
- **Dietitian/nutritionist software:** ~$1.1–1.2B (2025) → $1.8–2.8B by 2032–34 at ~7–10% CAGR; Europe flagged as high-growth; leaders Nutrium, Healthie, NutriAdmin.
- **GLP-1 shift:** Ozempic/Wegovy users eat far less → micronutrient-deficiency risk, pushing the market from calorie-counting toward **micronutrient adequacy** — directly favourable to the 168-nutrient wedge.
- **Personalized nutrition mainstreaming:** ZOE (100K+ members, biomarker-led) raises the bar on what "personalized/science" means — Mehungry's personalization is survey/preference-based, not biomarker-based.
- **AI logging is now table stakes** (MacroFactor/Lifesum/Samsung Food photo/voice logging). Mehungry has AI *generation* but not AI *food-logging* — the daily-use AI feature users actually want.
- **Shakeout:** PlateJoy shut down (2025) — standalone paid meal-planning is a fragile business.
- **EU labelling:** the Commission effectively shelved mandatory Nutri-Score (March 2025); EU health-claim rules still constrain how boldly the condition→compound layer can advise.

(Full sources with URLs + access dates in [file 10](10-sources-and-evidence.md).)

## Bottom line

Mehungry's defensible wedge is **"USDA-exact nutrition applied to AI-generated and community recipes," riding the GLP-1 micronutrient tailwind** — but it attacks Cronometer's turf (which already does verified 84–95 nutrients with 10M users and native apps) *while* spreading across three more incumbent-held markets. The three biggest threats to PMF are **web-only in a phone-first category, two-sided cold-start, and diffuse positioning.** Prove the nutrition-exactness wedge (E1/E6) and dietitian liquidity (E3) with cheap experiments before investing further in the social and science layers.
