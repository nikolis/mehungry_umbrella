# Product Foundation

The one authoritative statement of **what M3Hungry is, who it's for, and the rules it's
built on.** Everything else — the landing page, onboarding, nav, roadmap — should trace back
here. When a product decision contradicts this doc, either the decision is wrong or this doc is
out of date; reconcile the two, don't let them drift.

> **Status:** living. Current positioning set by the **2026-10-26 nutritionist-led
> repositioning** (see [§ How we got here](#how-we-got-here)). This is the *intended* product,
> not the measured one — for traction reality read [`app_status.md`](app_status.md), for the
> current tactical plan read [`growth_plan.md`](growth_plan.md).

---

## One line

**M3Hungry helps independent nutritionists get discovered and run their practice — reaching
clients through a public library of exact-nutrition recipes and food data, then managing them
(plans, appointments, payments) in one place.**

The nutritionist is always the **subject** of the pitch. The public consumer content (`/foods`
nutrient pages + `/home/:id` recipe pages + the social posts that point at them) is the
**channel**, not a second product: it's a one-directional top-of-funnel — content reach →
nutritionist discovery → the nutritionist converts and retains the client. We lead with the
nutritionist and let the content funnel into them; we do **not** pitch M3Hungry as a two-sided
marketplace to seed from both ends at once. (The advice stays 100% the nutritionist's — see
[principles](#principles--non-negotiables).)

## The problem we solve

Independent nutritionists and dietitians juggle a scattered toolchain: a social profile to be
found, a spreadsheet of clients, a calendar for appointments, a payment method, and hours of
manual meal-plan math. None of it talks to each other, and the meal-plan math is exactly the
part that's both the most time-consuming and the most error-prone. M3Hungry collapses that into
one workspace — and makes the nutrition math **exact** (see [the differentiator](#the-differentiator)).

## Who it's for

| Ring | Who | What they get | What they pay |
|---|---|---|---|
| **Primary** | Professional nutritionist / dietitian | Discoverable public profile + directory + articles; client roster, records, appointments, payouts; AI that drafts plans | **Pro** — €29.90/mo |
| **Second ring** | That nutritionist's own clients | A living, exact meal plan from their nutritionist; the app to log food against it | Free / **Plus** €9.99/mo |
| **Proof-engine edge** | Self-serve consumers who arrive via food-nutrition search | The public `/foods` nutrition database; self-planning with the same AI | Free / **Plus** |

The strategic order matters: **win the nutritionist, and their clients come with them.** That
is also the cold-start fix — we do not try to spark a consumer social graph from zero (it's been
tried; it's dead — [`app_status.md` §3](app_status.md)).

## Positioning — one audience, two acts

- **Act 1 (the lead):** *"Grow your nutrition practice. Keep it 100% yours."* — a discoverable
  profile that brings clients in, a workspace to manage them, and an AI assistant for the grunt
  work.
- **Act 2 (the amplifier):** automated, 168-nutrient-exact **meal planning** — sold to the pro
  as leverage ("serve more clients") and shipped as the headline consumer **Plus** feature. One
  build earns on both sides.

## The differentiator

Every recipe and meal is built from **real USDA FoodData Central ingredients**, so the app shows
the **full 168-nutrient profile per serving — calculated, not estimated.** This is the moat:

- It's overkill for a casual home cook but **decisive credibility for a professional** who has
  to put their name on a plan. "Exact, not estimated" is a claim generic calorie trackers
  cannot honestly make.
- It is the one surface already earning organic search (Greek nutrient lookups on `/foods` —
  [`seo.md`](seo.md)). We keep `/foods` as the public **proof engine** behind the pro pitch; we
  do **not** delete the consumer side.

## Principles / non-negotiables

1. **Still 100% you.** AI *drafts*; the nutritionist reviews, adjusts, and approves. The
   assistant never sends advice to a client on its own. This is the spine that separates the
   product from a chatbot and lets a credentialed professional own the output.
2. **No fabricated metrics.** Marketing and UI show real data where it exists and a clearly
   *labeled* illustrative preview where it doesn't — never an invented person, follower count,
   or rating. (See the hero fallback in [`professionals/professional_profiles.md`](professionals/professional_profiles.md).)
3. **Exact over approximate.** Nutrition is computed from USDA data, not guessed. If we can't be
   exact, we say so.
4. **Stay inside the YMYL line.** We do **not** publish condition-specific dietary advice to the
   public — condition pages are nutritionist-gated and off the sitemap until the product
   formally qualifies as a regulated health-information service. See `CLAUDE.md` (Health
   context) and [`seo.md`](seo.md). Advice reaches a client **through their nutritionist**, not
   from an anonymous page.
5. **Reuse, never duplicate the calc.** One domain function per computation, shared across
   LiveView + REST, so nutrition totals can't silently diverge (see the REST↔LiveView parity
   rule in `CLAUDE.md`).

## What it is *not*

- **Not** a generic recipe-social network. The feed exists, but it is not the product and must
  not be the first thing a new user sees.
- **Not** a gym-macro calorie counter. The depth is for professional nutrition, not step-count
  gamification.
- **Not** a medical device. We surface facts and let a qualified human advise; we do not
  diagnose or prescribe to the public.

## How the pieces ladder up

```
Nutritionist (Pro, pays)
  ├─ public profile + directory + articles   → gets discovered  (reach)
  ├─ clients · records · appointments · payouts → runs the practice (workspace)
  └─ AI planner + recipes (168-nutrient exact) → does the busywork (leverage)
        │  drafts → nutritionist approves → assigns
        ▼
  Clients (Free/Plus)  → live exact meal plan, log food against it
        │
        ▼
  /foods public nutrition DB  → organic search → funnel floor + credibility proof
```

## How we got here

- The product began as a broad consumer "food/recipe social platform" and accreted five
  co-equal value props (tracking, meal planning, social, AI, a nutritionist tier). Users
  reported they couldn't tell what it was for.
- **2026-10-26:** repositioned to lead with the professional nutritionist (the paying customer
  whose tooling was already built but buried), with meal planning as act 2. First shipped change
  was the `LandingLive` hero. Rationale, ranked roadmap, and the one tension to respect (don't
  abandon the consumer `/foods` demand) are captured in **memory → *Nutritionist Repositioning***
  and in [`professionals/professional_profiles.md`](professionals/professional_profiles.md).

## Business model (summary)

Three tiers, enforced by `Mehungry.Subscriptions` (owner email bypasses quotas). Full detail in
[`subscriptions_billing.md`](subscriptions_billing.md).

| Tier | Price | AI recipes / meal plans per month | For |
|---|---|---|---|
| Free | €0 | 0 / 0 | Clients, self-planners, proof-engine visitors |
| `m3hungry_plus` | €9.99/mo | 15 / 4 | Consumers who want automated planning |
| `pro` | €29.90/mo | 30 / 10 | **Nutritionists** — adds the client/appointment/payout workspace |

## Related docs

- [`app_status.md`](app_status.md) — measured traction (the honest denominator this doc's
  *intent* is tested against).
- [`growth_plan.md`](growth_plan.md) — the current time-boxed tactical plan. *(Note: predates the
  nutritionist pivot; reconcile when next revised.)*
- [`professionals/professional_profiles.md`](professionals/professional_profiles.md) — the
  nutritionist profile + public directory + the nutritionist-led marketing landing.
- [`normal_user.md`](normal_user.md) — walkthrough + UX review of the non-nutritionist
  (consumer / client) surface, measured against the principles above.
- `CLAUDE.md` — the engineering map (contexts, conventions, the Health/YMYL boundary).
