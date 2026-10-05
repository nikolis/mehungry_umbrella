# 05 — Competitive Analysis

*Research date 2026-10-05. Pricing/traction figures are dated and cited in [file 10](10-sources-and-evidence.md); where sources conflict a range is shown. Mehungry capabilities are from the code.*

## The strategic read

**No single competitor combines deep nutrients + AI recipes + social + condition-science + a nutritionist marketplace.** Mehungry's uniqueness is **real but it is "breadth," not "depth"** — and breadth is the weaker moat, because each individual axis is beaten by a focused, mobile-native, better-funded incumbent. Mehungry is not one product in one market; it straddles four, each with entrenched players.

## Competitor profiles

### Nutrient tracking — the closest, most defensible battleground

**Cronometer** — *the single closest comparator; owns the "deep micronutrient + verified data" wedge Mehungry is attacking.*
- Target: biohackers, GLP-1 users, keto/carnivore, longevity/quantified-self, + dietitians (Pro tier).
- Data: USDA SR Legacy + NCCDB (Univ. of Minnesota) + verified manufacturer data — "lab-grade" for whole foods. Tracks **84 nutrients free / ~95 Gold**.
- Pricing (2026): Gold ≈ **$8.99–10.99/mo or $49.99–59.99/yr**; unusually generous free tier (micros free).
- Traction: **10M+ users, 7.5M+ downloads, 4.7★/144K reviews**; **bootstrapped/independent**.
- **Implication:** "168 vs 4 nutrients" is a real wedge against MyFitnessPal — **not against Cronometer** (which tracks ~90 verified). Mehungry's 168 is USDA-only; it must justify *why 168 matters* and avoid implying rivals track "4."

**MyFitnessPal** — mass-market calorie counter, the "4 nutrients" foil. Huge (largely user-submitted) food DB with accuracy issues. Pricing (2026): Premium **$19.99/mo or $79.99/yr**; Premium+ **$24.99/mo or $99.99/yr**. Added GLP-1 logging.

**Lose It!** — simpler calorie counter. Premium **$79.99/yr, Lifetime $299.99**, free basic tier.

**MacroFactor** — premium adaptive macro coach. **$11.99/mo, $71.99/yr, no free tier**. Differentiator: dynamic target adjustment + fastest AI photo/barcode/label logging. Shallower micros.

### Food scoring / EU-centric

**Yuka** — EU-born (France) barcode food & cosmetics scanner; **~56–80M users** across 12 countries. Scoring 60% nutrition (Nutri-Score) / 30% additives / 10% organic. Free core; Premium **~€15/yr**. Owns EU "is this product healthy?" mindshare and the Nutri-Score vocabulary Mehungry's EU users already know.

**Open Food Facts** — nonprofit crowdsourced DB, **4.85M products**, Digital Public Good. Not a consumer-app rival — rather **free infrastructure** Mehungry could tap for EU branded/packaged goods (where USDA-only data is weak).

### AI meal planning

**Eat This Much** — auto meal-plan generator (~5,000 recipes to targets). Free tier; Premium **~$5–15/mo**. Closest to Mehungry's "generate a weekly plan to targets."
**Samsung Food (ex-Whisk)** — recipe save + planner + shopping list; free, **Plus ~$6.99/mo** adds AI plans + pantry recognition. Backed by Samsung distribution.
**Mealime** — quick weeknight dinners; **Pro ~$2.99/mo**.
**PlateJoy** — **shut down 2025** (acquired by RVO Health) — signals standalone paid meal-planning is hard.
**Paprika** — manual recipe manager (one-time ~$5/platform); loyal power users; no AI/nutrition depth.

### Behaviour-change / science-led

**ZOE** — personalized nutrition via CGM + gut microbiome + blood-fat testing; PREDICT trials, Tim Spector brand. **~$399 kit + ~$25–60/mo**; first-year ≈ $700–1,100. **100K–130K+ paying members (2025)**; raised $15M (2024). **Most relevant to Mehungry's "science" positioning** — but ZOE's moat is proprietary clinical trials + personal biomarkers, far deeper than literature-mined compounds.
**Noom** — psychology-based weight loss, now heavily GLP-1. **~1.5M paying subscribers (end 2023)**, $17–70/mo; GLP-1 program hit $100M run-rate within 4 months.
**Lifesum** — EU-born (Sweden) tracker + AI text logging. Free; Premium **~$7.49/mo**; **10M+ installs**. A real EU consumer-nutrition brand in Mehungry's price band.

### Nutritionist / dietitian practice SaaS — where Mehungry's Pro competes

**Healthie** — clinical EHR + telehealth + insurance billing, API-first. Free starter (≤10 clients); **Core $19 / Essentials $49 / Plus $129 / Group $149+/mo**. US-centric.
**Practice Better** — practice management + meal planning (via That Clean Life) + programs. **Free (3 clients), Starter $35, Pro $59, Plus $89, Team $145/mo**.
**Nutrium** — EU-origin (Portugal): scheduling, telehealth, assessments, meal plans, invoicing. **~€25–88/mo**. **The most direct EU comp to Mehungry's Pro.**
**NutriAdmin** — all-in-one practice suite. From **~$24.99/mo**.
**That Clean Life** — meal-planning content engine, 8,000+ dietitian recipes, white-label. **$30–60/mo**.

**Key gap vs these:** incumbents offer **insurance billing, clinical EHR/charting depth, white-label**. Mehungry's Pro is clinically thinner but uniquely bundles a **consumer-facing SEO marketplace + client logging in the same app** — which pure back-office SaaS does *not* do (they don't send the dietitian clients). *Caveat: Mehungry's marketplace booking currently collects no payment — see [feature inventory](02-product-feature-inventory.md).*

## Comparison matrix

Legend: ✅ yes · ⚠️ partial/shallow · ❌ no · **V** verified (source/code) · **A** assumed/inferred.

| Capability | **Mehungry** | Cronometer | MyFitnessPal | MacroFactor | Yuka | Eat This Much | ZOE | Noom | Nutrium | Healthie/PB |
|---|---|---|---|---|---|---|---|---|---|---|
| Nutrient depth | 168 (V) | 84–95 (V) | ~14 (V) | ~54 (V) | Nutri-Score (V) | macro (A) | biomarker (V) | macro (A) | clinical (A) | integrated (A) |
| Data credibility | USDA only (V) | USDA+NCCDB+verified (V) | crowdsourced (V) | curated (A) | Nutri-Score+OFF (A) | own DB (A) | own trials (V) | own (A) | clinical (A) | integrated (A) |
| AI recipe gen | ✅ (V) | ❌ | ❌ | ⚠️ photo-log (V) | ❌ | ⚠️ algo (A) | ❌ | ⚠️ (A) | ❌ | ❌ |
| AI meal-plan gen | ✅* (V) | ❌ | ⚠️ Premium+ (V) | ❌ | ❌ | ✅ (V) | ⚠️ (A) | ❌ | ⚠️ templated (A) | ⚠️ via TCL (A) |
| Social / UGC | ✅ (V) | ❌ | ⚠️ legacy (A) | ❌ | ⚠️ reviews (A) | ❌ | ⚠️ community (A) | ⚠️ (A) | ❌ | ❌ |
| Condition guidance | ✅ science layer (V) | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ personalized (V) | ✅ behavioral (A) | ⚠️ clinician (A) | ⚠️ clinician (A) |
| Nutritionist marketplace | ✅ SEO+booking† (V) | ❌ | ❌ | ❌ | ❌ | ❌ | ⚠️ in-house (A) | ❌ | ❌ back-office (V) | ❌ back-office (V) |
| EU / multi-language | ✅ en/el, € (V) | ⚠️ (A) | ✅ (A) | ⚠️ EN (A) | ✅ EU-native (V) | ⚠️ (A) | ✅ UK/EU (V) | ⚠️ US (A) | ✅ EU PT (A) | ⚠️ US (A) |
| Pricing (consumer) | Free/€9.99/€29.90 (V) | ~$9/mo (V) | ~$20/mo (V) | ~$12/mo (V) | free/€15yr (V) | ~$5–15/mo (V) | ~$700+/yr (V) | $17–70/mo (V) | n/a | n/a |
| Platform | **Web only** (V) | iOS/Android/web (V) | iOS/Android/web (V) | iOS/Android (V) | iOS/Android (V) | web/mobile (A) | iOS/Android (V) | iOS/Android (V) | web/mobile (A) | web/mobile (A) |

\* Mehungry's "AI meal-plan" assigns the user's **existing** recipes to days (not novel generation); blueprint is an inert hint. † Marketplace **booking collects no payment** in the current code.

## Where Mehungry is better / comparable / weaker

- **Meaningfully better:** USDA-exact nutrition on *generated & community* recipes; EU/Greek localization + a pro↔client closed loop no back-office SaaS offers.
- **Comparable:** AI meal-planning (vs Eat This Much/Samsung Food); consumer price point.
- **Weaker:** no native mobile app (every comp has one); nutrient-tracking credibility vs Cronometer's verified NCCDB; "science" depth vs ZOE's trials; clinical depth (insurance/EHR) vs Healthie; social network effect vs Instagram/Pinterest.

## Crowding, white space, defensibility

- **Most crowded:** consumer calorie/macro tracking and the recipe social feed.
- **Underserved white space:** (a) EU/Greek-localized dietitian platform that *also* acquires clients; (b) condition-specific nutrition for a single niche (anti-inflammatory/IBS/kidney) — *gated by the health-claims/MDR risk*; (c) USDA-exact nutrition on shared/AI recipes.
- **Table stakes (not advantages):** AI recipe/meal-plan generation, a food database, barcode logging — expected, not differentiating.
- **Defensible vs copyable:** Greek localization + a liquid local dietitian network + accumulated client relationships are defensible (local-network and switching-cost moats). The 168-number, the social feed, and generic AI generation are **easily copied**.

## Bottom line

Attacking Cronometer head-on (deep nutrients, web-only, no budget) is the weakest fight. The credible, defensible position is the **EU/Greek dietitian platform** where the consumer features become the client-facing layer — see [positioning](06-positioning-strategy.md).
