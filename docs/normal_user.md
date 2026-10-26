# The Normal (Non-Nutritionist) User

A walkthrough **and UX review** of everything a regular signed-in consumer — and
the anonymous visitor who becomes one — can see and do in M3Hungry. This is the
"second ring" and "proof-engine edge" of the audience, not the paying subject of
the product; read [`product_foundation.md`](product_foundation.md) first for *why*
the consumer side exists and the rules it must respect. When this doc and the
foundation disagree, the foundation wins — flag the drift here.

> **Scope:** the `:maybe`, `:default`, and `:default3` live sessions + the public
> controller routes in `router.ex`. Explicitly **out of scope:** the nutritionist
> workspace (`/nutritionist/**`, see [`professionals/professional_profiles.md`](professionals/professional_profiles.md))
> and the admin panel (`/professional/**`).

---

## Who this user is

Per the [foundation's audience rings](product_foundation.md#who-its-for), a "normal
user" is one of two:

- **The nutritionist's client** (second ring) — arrives via an invitation, gets a
  living meal plan + a messaging line to their nutritionist, logs food against the
  plan. Free or **Plus** (€9.99/mo).
- **The self-serve consumer** (proof-engine edge) — arrives via organic food-nutrition
  search on `/foods`, browses recipes, maybe self-plans. Free or **Plus**.

Both are detected as *not* a nutritionist (`Mehungry.Subscriptions.nutritionist?/1`
is false); the whole nutritionist workspace + the "Your practice" nav block are
hidden from them.

## How they enter

| Visitor state | Lands on | Route |
|---|---|---|
| Anonymous | Nutritionist-led landing (`LandingLive`) | `/` → `/:locale/welcome` |
| Signed-in consumer | Consumer home **feed** (`HomeLive`) | `/` → `/:locale/home` |
| Signed-in nutritionist | Practice dashboard (out of scope) | `/` → `/nutritionist` |

`HomePageController.home/2` is the single funnel point; `user_return_to` deep links
are honoured upstream in `UserAuth.log_in_user`. Registration is at `/register`
(IP-rate-limited + Turnstile), OAuth via Facebook/Google/Instagram. A client whose
account was created *for* them by a nutritionist claims it via `/claim/:token`.
First login after signup opens the **2-step onboarding modal**
(`live/onboarding/form_component.ex`): diet preference + language, then a daily
calorie target. Diet choice persists to `UserProfile.diet` and regenerates the
category rules that drive diet-mode filtering app-wide.

## The feature surface

### Navigation (`main_menu` desktop rail / `mobile_menu` bottom bar)

The consumer's primary nav, top to bottom: **Browse · Foods · Create Recipe ·
Calendar · Basket · Give Feedback**, then conditional badges (Tutor Invitations,
Messages, Friends) and a **"Manage subscriptions"** (upgrade) link, with
language toggle (EN/ΕΛ) + Profile/Login at the bottom. The "Your practice" block
and "Admin Panel" link are gated off for this user.

### Discover & browse

| Feature | What the user does | Entry point |
|---|---|---|
| **Home feed** | Scroll a paginated post feed (recipe cards + weekly-plan share cards), upvote/downvote, open a recipe, infinite "load more"; feed is diet-mode filtered from the saved profile | `HomeLive.Index` (`/home`) |
| **Browse / search** | One search box over recipes with facets: hashtag (`/search/hashtag/:h`), ingredient (`/search/ingredient/:i`), nutrient-claim chips (Iron/Calcium/Vit C/Potassium/Magnesium), free text, and condition-prioritized browse; toggles into blueprint / meal-plan search modes | `RecipeBrowserLive.Index` (`/browse`, `/search/*`) |
| **Foods nutrition DB** (the proof engine) | Browse/search USDA-backed food **species**, filter by bioactive compound, cursor-paginated; localized (EL names) | `FoodsLive.Index` (`/foods`) |
| **Species detail** | Full per-100g nutrition table per ingredient of a species, macro highlights, bioactive **compounds** (async), research/studies, sample recipes; SEO JSON-LD on the dead render | `SpeciesDetailLive.Index` (`/foods/:slug`) |
| **Public nutritionist directory** | Browse/search public nutritionist profiles + their articles; request a booking | `PublicNutritionistLive.{Index,Show,Article}` (`/nutritionists`) |
| **Public meal plans & blueprints** | SEO-indexed weekly meal plans + meal blueprints with full nutrition | `MealPlanLive`, `BlueprintLive.Show` (`/meal-plans`, `/blueprints/:slug`) |

### Recipe interaction (`RecipeDetailsComponent`)

Open a recipe to: **save/unsave**, comment + reply + vote on comments, share to
social (Facebook / Instagram / Pinterest), generate an insight social-graphic,
add to the calendar, and import ingredients to the basket. Full 168-nutrient
breakdown per serving + nutrient-claim badges ("High in Iron") are shown — the
[differentiator](product_foundation.md#the-differentiator) in the consumer's hands.

### Create & plan

| Feature | What the user does | Entry point | Gate |
|---|---|---|---|
| **Create recipe** | Manual multi-step form; **AI generate** from a prompt; **AI import from URL**; (Spoonacular import is shadowed/off) | `CreateRecipeLive.Index` (`/create_recipe`) | AI paths consume `recipe_generation` quota |
| **Calendar / meal plan** | Per-day meal slots; **AI plan a week**; day notes; per-day **avoid-foods** personal list w/ flagging; copy-a-meal-to-today; day-summary sodium/sat-fat badges; follow/unfollow a blueprint; **generate a week share card** + **post it to the feed** | `CalendarLive.Index` (`/calendar`) | AI plan consumes `meal_plan` quota |
| **Basket / shopping** | Shopping baskets + items; add USDA-searched items or custom ingredients; import a recipe's or a meal's ingredients | `ShoppingBasketLive.Index` (`/basket`) | free |
| **My ingredients** | Create/edit personal ingredients | `MyIngredientLive.Form` | free |

### Identity, social & profile

| Feature | What the user does | Entry point |
|---|---|---|
| **Profile** | Tabbed: **Saved · Created · Meal Plans**; hero links to edit, connections, ingredients; unsave/delete recipes, delete meal plans, disconnect social, unlink nutritionist, regenerate recipe images | `ProfileLive.Index` (`/profile`) |
| **Friends** | Send/accept friend requests (badge counts pending) | `FriendsLive.Index` (`/friends`) |
| **Messages** | Chat line with *their* nutritionist (only shown if they have an assignment) | `MessagesLive.Index` (`/messages`) |
| **Tutor invitations** | Accept/decline a nutritionist's invitation (badge) | `NutritionistLive.UserInvitations` (`/notifications/invitations`) |
| **Upgrade / billing** | See quota usage, pick Plus/Pro monthly/yearly, Stripe checkout + billing portal | `UpgradeLive.Index` (`/upgrade`) |
| **Feedback** | Submit product feedback | `FeedbackLive` (`/feedback`) |

### Subscription tiers the consumer sees

| Tier | Price | AI recipes / plans per month |
|---|---|---|
| Free | €0 | **0 / 0** |
| `m3hungry_plus` | €9.99/mo (€99/yr) | 15 / 4 |
| `pro` | €29.90/mo | 30 / 10 (nutritionist tier; shown but off-audience) |

Enforced by `Mehungry.Subscriptions.{check_quota,record_usage}`; owner email bypasses.
See [`subscriptions_billing.md`](subscriptions_billing.md).

### Localization

Full EN/EL localization: locale-prefixed URLs (`/en/…`·`/el/…`), Gettext UI
strings, localized species/ingredient/nutrient names, hreflang/canonical for SEO.
See [`localization.md`](localization.md). Language switch works anonymously.

---

## UX review — findings

Grounded against the [foundation's principles and "what it is not"](product_foundation.md#what-it-is-not).

### What works well

- **The proof engine is genuinely strong.** `/foods` → species detail gives real,
  exact per-100g nutrition + compounds + research + sample recipes, SEO-indexed and
  localized. This is the one surface earning organic search and it reads as
  credible — exactly the role the foundation assigns it.
- **"Exact over approximate" is visible to the consumer** — 168-nutrient breakdown +
  NRV badges on every recipe and meal, not estimates. The differentiator isn't
  buried behind the pro tier.
- **Calendar depth is real** — AI week planning, day notes, a personal avoid-list
  with flagging, copy-meal, and day-summary sodium/sat-fat badges make the
  self-tracking loop coherent for a client living against a plan.
- **Honest gating** — AI quota is enforced per tier, owner bypass aside; no
  fabricated metrics in the landing hero (falls back to an honest preview).

### Frictions & tensions to watch

1. **The signed-in consumer's first screen is the feed** — `/` routes a logged-in
   consumer straight to `HomeLive` (the post feed). The foundation is explicit: *"the
   feed… must not be the first thing a new user sees"* and *"not a generic
   recipe-social network."* Anonymous visitors correctly get the nutritionist-led
   `/welcome`, but a freshly-registered consumer lands in the thing the foundation
   says to de-emphasize. **Candidate fix:** land new consumers on `/foods` or a
   plan-oriented home, not the social feed.
2. **The nav leads with social/creator tools, not the value prop.** Browse · Create
   Recipe · Calendar · Basket front the rail. "Create Recipe" and the social feed
   push the "recipe-social network" identity the foundation disowns; meal planning
   (the act-2 headline consumer feature) is just "Calendar" with no signal that it's
   the point. The exact-nutrition DB (`Foods`) is a mid-list item.
3. **Free tier has 0 AI quota, but the AI entry points are first-class in the nav.**
   A free user clicks "Create Recipe" → AI generate / "Calendar" → AI plan week and
   hits a quota wall at `0`. The upsell moment is fine, but the nav promises
   capability the default tier can't exercise at all — verify the empty-state copy
   routes cleanly to `/upgrade` rather than reading as a failure.
4. **"Manage subscriptions" is an opaque label for the upgrade CTA.** For a free
   user with nothing to manage, the primary monetization link reads like account
   settings, not "get Plus." Consider value-first copy ("Go Plus" / "Unlock AI
   planning").
5. **Overlapping "social" surfaces dilute focus.** Friends, the post feed, comments,
   and social-sharing coexist with the client↔nutritionist Messages line. For the
   second-ring *client*, the relationship with their nutritionist is the point; the
   friend graph is the cold-start consumer-social idea the foundation calls
   [dead](product_foundation.md#how-we-got-here). Worth asking which of these earn
   their nav slot.
6. **Condition/health advice is correctly absent** — condition pages are
   nutritionist-gated and the old public ones now 410. The consumer surface stays
   inside the [YMYL line](product_foundation.md#principles--non-negotiables). ✔
   (This is a *pass*, noted so it isn't "fixed" into a regression.)

### Alignment summary

| Foundation principle | Consumer surface honours it? |
|---|---|
| Not a generic recipe-social network | ⚠️ Partially — feed is the signed-in home; creator/social tools lead the nav |
| Feed not first thing a new user sees | ⚠️ Anonymous ✔, signed-in consumer lands on the feed |
| Exact over approximate | ✔ 168-nutrient + NRV badges everywhere |
| Stay inside the YMYL line | ✔ Condition pages gated/410, off the sitemap |
| No fabricated metrics | ✔ Honest landing fallback |
| Proof engine funnels to the nutritionist | ⚠️ `/foods` is strong, but the consumer path to a nutritionist (the directory) is low in the nav and not the dominant CTA |

---

## Related docs

- [`product_foundation.md`](product_foundation.md) — the source of truth this review
  traces back to (audience rings, principles, what-it-is-not).
- [`app_status.md`](app_status.md) — measured consumer traction reality.
- [`professionals/professional_profiles.md`](professionals/professional_profiles.md) —
  the nutritionist side the consumer funnels into.
- [`subscriptions_billing.md`](subscriptions_billing.md) — the Free/Plus tiers and quota.
- [`localization.md`](localization.md) — the EN/EL surface.
</content>
</invoke>
