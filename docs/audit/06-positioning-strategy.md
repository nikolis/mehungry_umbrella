# 06 — Positioning Strategy

*Grounded in the code + the [competitive](05-competitive-analysis.md) and [market-fit](04-market-fit.md) findings. Budget/conversion figures are labelled estimates.*

## The focus problem to confront first

Mehungry is **five products in one** — a deep nutrient tracker, an AI recipe/meal-plan generator, a recipe social network, a health-science engine, and a B2B nutritionist marketplace + practice SaaS. Each is a crowded, well-funded category. **A solo, bootstrapped, web-only founder with near-zero marketing budget cannot win five land-grabs at once.** The strategy must collapse the five into **one wedge where breadth becomes a feature, not a liability.**

Decisive constraints shaping every recommendation:
- **Web-only, no native app** → fatal for a *consumer daily-logging* position; acceptable for a *professional desktop* tool.
- **Solo operator, no paid-media budget** → favours direct outreach + high-intent SEO + product-led loops.
- **Free tier ships 0 AI generations** → the most differentiated feature is invisible until payment (a conversion problem).
- **Marketplace collects no payment yet** (verified) → any booking-revenue thesis is a *build*, not a current asset.
- **Health claims** create legal/credibility exposure (R1/R2) that must be messaged defensively.

## Ideal Customer Profile

### Primary — the independent EU dietitian/nutritionist (beachhead: Greece, then EU)
- **Who:** university-trained dietitian, 25–45, running a solo or 2–3-person private practice, 15–80 active clients; software-comfortable, not technical.
- **Today:** juggles Excel meal plans, PDF handouts, WhatsApp follow-ups, paper intake, a separate booking tool; clients log food in a *different* app the dietitian can't see; growth relies on word-of-mouth + a weak Instagram.
- **Pain:** fragmented toolchain; no visibility into what clients eat between sessions; slow to build accurate plans; unpredictable client acquisition; chasing payments/no-shows.
- **Willingness to pay:** high and proven — Nutrium charges ~€25–88/mo. Pro at €29.90 undercuts the category and (once built) adds a **lead-generating public marketplace** + online booking.
- **Why first:** B2B monetizes faster and more durably; willingness-to-pay already exists; and this persona **turns "too broad" into "all-in-one for me and my clients"** — the consumer tracker, AI plans, and recipe library become the client-facing layer the dietitian hands out.

### Secondary — the "quantified / condition-aware" home cook
28–50, health-motivated, already tracks food or follows a therapeutic diet; wants micronutrient-level truth. WTP moderate (€9.99 Plus). **Role: the SEO/content audience and the referral fuel for the primary ICP — they become the dietitians' clients — not the group to build the product around.**

## Positioning

- **Highest-value problem to own:** *Independent nutrition professionals have no single tool that runs their practice **and** gives them real-time, nutritionally exact visibility into what their clients eat — and that also helps new clients find them.*
- **Category:** **All-in-one practice + client platform for independent dietitians** (practice management + meal planning + a client-facing nutrient-tracking app + a client-acquisition marketplace). Not "another calorie tracker."
- **Value proposition:** *Run your whole nutrition practice — plan, book, get paid, and see what your clients actually eat — in one GDPR-native platform that also sends you new clients.*
- **Strongest defensible differentiator:** the **closed loop between professional and client in one system** + a public SEO marketplace that generates demand + EU/Greek localization + price. Nutrium/Healthie give the dietitian a dashboard; Cronometer gives the consumer a tracker; **only Mehungry puts the client's 168-nutrient log, the AI meal plan, and the dietitian's practice tools in the same product.**
- **Most credible alternative to position against:** **Nutrium** (EU/GDPR practice-management leader, pricier, not Greek-localized, doesn't bring clients). Secondary foils: Healthie (US-centric) and, for the consumer layer, Cronometer.
- **Reasons to choose:** one subscription replaces 3–4 tools; a marketplace that *earns* its fee by acquiring clients; GDPR/EU-native; Greek-language; cheaper than Nutrium; clients get a genuinely deep tracker + AI plans free.
- **Reasons NOT to choose (be honest):** no native mobile app yet (clients log on web/PWA); marketplace is young (thin liquidity/reviews); **booking payments not built yet**; single-founder support; not a certified medical device.
- **Positioning gaps / credibility risks:** the homepage currently sells a *consumer* story ("168 nutrients") and competes head-on with Cronometer where Mehungry is weakest; "scientific"/"168"/"nutrient interactions" invite health-claim scrutiny; the marketplace cold-start signals low trust; a solo/Gmail brand needs offsetting proof.

## Three positioning directions

### Direction A — Consumer "deep-nutrient + science" tracker (vs Cronometer/ZOE)
- Target: quantified home cooks, biohackers, therapeutic-diet followers. Value: "168 nutrients, exact not estimated."
- **Why risky:** Cronometer already owns this with a mature **mobile** app; daily logging is a mobile behaviour, so web-only is close to disqualifying; ZOE owns "science-personalized." Requires a native app + consumer marketing budget the founder lacks. **Evidence required:** native app, validated DB depth, defensible accuracy claim.

### Direction B — AI recipe/meal-planning for a condition niche (anti-inflammatory / IBS / kidney)
- Value: "recipes & plans engineered for *your* condition, with foods to favour/avoid from published research." Differentiation: the `Health` condition→compound engine; the shipped "Anti-Inflammatory" indication is a natural first consumer.
- **Why risky:** **highest legal/credibility risk** (therapeutic claims — R1/R2); science tables may be sparse; still needs mobile + consumer CAC. **Evidence required:** populated, defensible condition data; medical/dietitian review; clinician endorsement.

### Direction C — B2B-first nutritionist practice + marketplace tool (EU/Greek dietitians) ✅ **RECOMMENDED**
- Target: the primary ICP. Value: "the all-in-one platform to run your practice, see what clients eat, and get discovered — in Greek, GDPR-native, for less than Nutrium."
- Differentiation: pro↔client closed loop + lead-gen marketplace + localization + price.
- **Trade-offs:** smaller TAM than consumer; requires a direct-sales motion (slower per logo, far cheaper per €); marketplace liquidity + payment-rails cold-start.
- **Evidence required:** 5–10 reference dietitians with testimonials; real public profiles with bookings; proof the tool saves hours and sources ≥1 client.

### Why C is recommended
1. **Resolves the focus tension without throwing code away** — tracker, AI plans, recipes, and science engine become *features the dietitian's clients receive*.
2. **Money is where willingness-to-pay is proven** — Nutrium sustains €25–88/mo; €29.90 is an easy "yes"; a future booking fee adds marketplace revenue incumbents lack.
3. **Fits a solo founder's channels** — you can personally close the first 20 Greek dietitians; impossible with 20,000 consumers.
4. **Web-only is acceptable** for a professional desktop workflow; patch the client-logging edge with a **PWA**, not a full native build.
5. **Greek localization is a real moat** against Nutrium/Healthie in the beachhead.

> Keep A/B alive only as **content/SEO surface** (condition articles, "deep nutrient" comparison pages) that funnels clients to dietitians — not as the product's identity.
>
> **Prerequisite for C's full thesis:** build the booking-payment flow (it doesn't exist) and fix the Phase-0 legal items (R1–R4, R6) before promoting the health/marketplace surface.

## Messaging (for Direction C)

**Positioning statement:**
> For independent dietitians and nutritionists in Greece and the EU who are tired of stitching together Excel, WhatsApp, and a booking app, **Mehungry** is the all-in-one practice platform that lets you plan meals, manage clients, get paid, and see exactly what your clients eat — while a public profile brings new clients to you. Unlike Nutrium or Healthie, it's GDPR-native, available in Greek, costs less, and gives your clients a genuinely deep nutrition app for free.

**Homepage (B2B variant):**
- **Headline:** *"Run your nutrition practice — and get discovered — in one place."*
- **Subheadline:** *"Meal plans, client management, online booking, and a client app that logs 168 USDA-backed nutrients. GDPR-native, in Greek and English, from €29.90/mo."*

**Three evidence-based benefit statements:**
1. *"See what your clients actually eat — not just what they tell you."* (clients log in the same system you plan in — `Plans` + client calendar view)
2. *"Build accurate meal plans in minutes."* (AI plans with every ingredient mapped to USDA FoodData Central — `AI.MealPlanGenerator`, `Food.*`)
3. *"Let new clients find and book you."* (public SEO profile + online scheduling — `Professionals`, Stripe Connect) *(payment collection to be completed)*

**Top objections → responses:**
1. *"I already use Nutrium/Excel."* → "Keep your workflow but add client-side food visibility and a booking channel Nutrium doesn't have — for less, in Greek. Import clients via CSV."
2. *"My clients won't use another app."* → "They get a free, genuinely useful tracker + their plan in it — and you see adherence between sessions. Works in the browser; no install."
3. *"Is the nutrition data trustworthy?"* → "Every value comes from USDA FoodData Central — we show the source, we don't invent numbers."
4. *"Is my clients' data safe/GDPR-compliant?"* → "EU-hosted, GDPR by design, payments via Stripe." *(Only say this once R3/R4/R7 are actually fixed.)*
5. *"It's new/small."* → "You're an early partner: direct founder access, your requests shipped, founding-member pricing locked."

**Messaging to AVOID (legal/credibility — see R1/R2):**
- No therapeutic/outcome claims ("treats/cures/prevents X", "lose X kg", "reverse inflammation"). Use "supports", "designed for", "foods commonly recommended for".
- Keep a persistent "Educational information, not medical advice" wherever the `Health` engine surfaces — **but remember a disclaimer does not make an unauthorised health claim lawful; the claim itself may need to go.**
- Don't overclaim the science ("proven by research", "clinically validated") — it's literature-derived and review-gated; say "based on published studies from PubMed", only where data is populated.
- Drop vague superlatives ("the most advanced nutrition AI"); don't imply medical-device/certification status; don't present AI meal plans as prescriptions.
- Don't claim "nutrient interactions per recipe" until it's actually shipped (currently unsubstantiated).

**Trust signals to add:** named founding-dietitian testimonials (headshots + practice names); "GDPR-native, EU-hosted, Stripe-secured" badges (once true); "Nutrition data from USDA FoodData Central"; a visible human founder (name/photo/LinkedIn, not a Gmail); active-practices/clients count once non-trivial; a sample public profile; a short demo video.
