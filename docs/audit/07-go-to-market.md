# 07 — Go-To-Market Plan

*For the recommended [Direction C](06-positioning-strategy.md) (EU/Greek dietitian platform). Budget/conversion figures are labelled estimates with stated assumptions; external benchmarks cited in [file 10](10-sources-and-evidence.md).*

## Principle: fix the funnel before buying traffic

Spending on acquisition now would waste it — the product loses users *before* the value lands. Close these leaks first:

1. **No native mobile app** → clients won't log food on a laptop; without client logging, the "see what clients eat" differentiator collapses. **Fix:** ship an installable **PWA** for client logging as a stopgap before any native build.
2. **Free tier = 0 AI generations** → the headline AI feature is invisible until payment; there's no "aha" to convert on. **Fix:** give a few free AI generations *or* a 14-day no-credit-card Pro trial (opt-in trials from organic convert far better — ~18% in cited 2025/26 benchmarks).
3. **Marketplace cold-start + no payment rails** → empty directory = low trust; and bookings collect nothing today. **Fix:** hand-seed 10–20 real founding-partner profiles; **build the booking-payment flow** (does not exist).
4. **Thin onboarding / long activation path** → a dietitian may never reach "first plan assigned." **Fix:** guided first-run with a sample client + one-click sample plan; CSV import front-and-centre.
5. **Credibility (solo/Gmail brand + science claims)** → add founder identity, testimonials, GDPR/USDA/Stripe trust marks, and disclaimers.

## Ranked channels (3 recommended, rest de-prioritized)

Ranking logic: fit to a solo founder, cost, speed-to-learn, execution effort.

### Channel 1 — Founder-led direct outreach to Greek dietitians *(highest fit)*
- **Why it fits:** B2B, small defined universe (Hellenic Dietetic Association / EFAD member lists, local clinics), native-language founder, high WTP. Cheapest, fastest learning per conversation.
- **First experiment:** personally contact 100 Greek dietitians (email/Instagram DM/LinkedIn), offering a free 1:1 setup + 3 months of Pro to 10 "founding partners."
- **Assets/effort:** a target list, a 3-line pitch, a 15-min demo, a founding-partner offer. ~2–3 weeks of founder time.
- **Budget (estimate):** €0–300 (list tooling/meetings). *Assumes founder's own time, no SDR.*
- **Primary metric:** # dietitians who assign a first meal plan to a real client within 14 days (activated design partners). **Supporting:** demo→trial rate.
- **Learning:** which pain (toolchain vs client-visibility vs lead-gen) drives adoption; the true objections.
- **Decision rule:** ≥8/100 activated → templatize & double down; <3 → the value prop or ICP is wrong; re-interview before scaling.

### Channel 2 — High-intent SEO (marketplace directory + condition/Greek content) *(best compounding; infra already exists)*
- **Why it fits:** the app already has SEO infra, sitemaps, a public `/nutritionists` directory, and el/en localization. Organic is the highest-quality top-of-funnel for SaaS; dual purpose — directory pages rank for "dietitian in [city]" (bringing the dietitian **clients**, which sells the dietitian on Mehungry), and condition/nutrition articles capture the secondary ICP who *become* those clients.
- **First experiment:** publish 10 programmatic directory/city pages + 10 Greek condition articles ("Διατροφή για [condition]"), each linking to "book a dietitian" and "list your practice."
- **Assets/effort:** content templates, 20 pages, internal linking. ~3–4 weeks.
- **Budget (estimate):** €200–1,500 (freelance Greek nutrition writer/editor). *Assumes founder does keyword/structure, outsources drafting.*
- **Primary metric:** organic sessions → booking requests + "list your practice" signups. **Supporting:** indexed pages ranking top-10.
- **Learning:** which queries convert; whether consumer traffic routes into professional demand.
- **Decision rule:** qualified pro/booking leads within 90 days of indexing → scale programmatically; pure vanity traffic → cut. *(Note the health-claims constraint R1 on condition-article wording.)*

### Channel 3 — Product-led free tier as a referral/lead loop *(cheapest scale; uses existing product)*
- **Why it fits:** the free consumer tier is a natural lead magnet; clients invited by a dietitian pull in their circle; satisfied dietitians refer peers (tight community). Near-zero marginal CAC.
- **First experiment:** add (a) a "find/invite your dietitian" prompt in consumer onboarding, and (b) a dietitian referral reward (+1 free month per referred practice). Instrument both.
- **Assets/effort:** 2 small in-product flows + email. ~2 weeks dev.
- **Budget (estimate):** €0–200. *Assumes in-house build.*
- **Primary metric:** referral coefficient (new activated accounts per existing active one). **Supporting:** invite send→accept rate.
- **Decision rule:** k > 0.3 within 60 days → invest in the loop; else deprioritize vs outreach.

### Supporting (lightweight): email lifecycle
Onboarding + activation + trial-conversion sequences are cheap table stakes — build them (with ePrivacy/consent compliance), but they *amplify* the channels above rather than source demand.

### Explicitly DE-PRIORITIZE
- **Paid ads** — no budget; consumer nutrition CPCs are brutal; low intent.
- **Product Hunt** — US consumer/tech audience; won't reach Greek dietitians; a spike, not a channel.
- **Recipe social growth / UGC** — a retention/SEO *feature*, not a standalone growth engine; don't try to "become a social network."
- **Broad consumer influencer marketing** — expensive, off-ICP for the B2B wedge.

## Funnel & metrics

**Funnel (Direction C):**
- **Discovery:** SEO directory/condition pages, founder outreach, referrals.
- **Activation (the real bottleneck):** dietitian signs up → imports/invites first client → assigns first AI meal plan → client logs first meal.
- **Retention:** recurring plan updates, client-adherence visibility, bookings, consultation notes.
- **Referral:** dietitian refers peers; clients invite friends; public profiles surface the brand.
- **Revenue:** Pro subscription (€29.90) [+ a future 5% booking fee, once payment rails are built] + consumer Plus (€9.99) secondary.

**North-star metric:** **Weekly Active Managed Client–Dietitian pairs** — a dietitian who, in the past 7 days, has a client that either logged a meal or received/updated a plan. Captures two-sided value; resists vanity inflation.

**Supporting metrics (not vanity):** dietitian activation rate (signup → first plan assigned ≤7 days); paid-Pro 3-month retention; client logging adherence (% invited clients logging weekly); booking volume (and GMV/fee once monetized); trial→paid rate. **Avoid:** raw registrations, pageviews, total recipes, social followers.

## 30 / 60 / 90-day plan

**Days 0–30 — Validate the wedge & stop the leaks**
- Interview 15–20 Greek dietitians; confirm the sharpest pain.
- Instrument the full funnel (activation steps, trial, retention events).
- Fix the two biggest leaks: free AI trial/sample generations + a client-logging PWA stopgap.
- Build a B2B landing variant ([§messaging](06-positioning-strategy.md)); add founder identity + trust marks + disclaimers.
- Hand-seed 10–20 real public dietitian profiles.
- **In parallel (non-negotiable):** ship Phase-0 legal fixes (R6 consent-gated GA, R7 correct false privacy statement, R4 safe+complete deletion, R8 AI-literacy).
- *Milestone:* 5 design-partner dietitians committed.

**Days 31–60 — Land design partners & light up SEO**
- Outreach to 100 dietitians; convert ≥10 founding partners (free/discounted Pro + white-glove CSV import).
- Ship guided onboarding (sample client + one-click sample plan).
- Publish first 10 directory/city pages + 10 Greek condition articles (health-claims-screened).
- Stand up email lifecycle.
- Begin the booking-payment build (prerequisite for marketplace monetization).
- *Milestone:* ≥8 activated partners; first organic booking leads.

**Days 61–90 — Prove retention, add loops, pick the scale channel**
- Launch dietitian referral + consumer "invite your dietitian" loops; measure k.
- Collect 5+ testimonials/case studies (hours saved, clients gained); publish them.
- Review activation/retention by channel; pick the one scalable motion (expected: outreach→referral + SEO directory).
- Decide on native-mobile investment from client-logging retention data.
- *Milestone:* ≥60% 3-month Pro retention among activated partners; a repeatable acquisition motion; first booking-fee revenue (if payment rails shipped).

## Bottom line

Win a **Greek dietitian beachhead** via founder-led outreach + high-intent SEO + a product-led referral loop — after fixing the free-AI and mobile-logging funnel leaks and the Phase-0 legal items. Undercut Nutrium on price, out-localize Healthie, and make the marketplace earn its fee by bringing clients in — which requires building the payment flow that does not exist today.
