# Nutritionist Features

The consolidated catalogue of everything the **professional nutritionist** — the
product's primary, paying audience — can do in M3Hungry, and where each feature
lives in the code.

> **Why this audience leads:** M3Hungry is nutritionist-led. The pitch, the
> landing page, and the roadmap all put the professional first; the consumer
> food layer is a top-of-funnel *channel* into nutritionist discovery, not a
> second product. The authoritative statement of purpose, audience, positioning,
> and non-negotiable principles is **[`product_foundation.md`](product_foundation.md)** —
> read it first; every feature below traces back to it. This file is the *how*
> (the shipped surface); `product_foundation.md` is the *why*.

Deeper design docs are linked inline; this page is the index, not a replacement
for them.

---

## Who is a "nutritionist" here

A nutritionist is any user on the **`pro`** subscription tier (€29.90/mo), or the
owner. The gate everywhere is `Mehungry.Subscriptions.nutritionist?/1`
(owner-email OR `tier == "pro"`); `grant_nutritionist/1` comps access without
Stripe. The gated LiveView surface lives under `/nutritionist/**`
(`live_session :nutritionist`, `on_mount: NutritionistAuthLive`), which bounces
non-pros to `/home`. Business model detail: [`subscriptions_billing.md`](subscriptions_billing.md).

## Two faces of the product

| Face | Audience | Chrome |
|---|---|---|
| **Public** — profile, directory, articles | Anyone (SEO-indexed) | consumer layout |
| **Workspace** — `/nutritionist/**` | The pro only | dedicated nutritionist sidebar (`layout_view.ex` `nutritionist_sidebar/1`) |

A logged-in pro now **lands on the workspace dashboard** on login
(`HomePageController.home` branches on `nutritionist?/1` → `/nutritionist`); the
consumer menu also hoists a **"Your practice"** group (Dashboard · Clients ·
Appointments) to the top for pros, on both the desktop sidebar
(`menu/main_menu.html.heex`) and the mobile bar (`menu/mobile_menu.html.heex`).

---

## 1. Get discovered (reach)

- **Public profile** — `/nutritionists/:slug` (`PublicNutritionistLive.Show`):
  photo, specialization, city/region, bio, contact, and a weekly-availability
  **booking wizard** (request → nutritionist accepts → email + `.ics`).
- **Directory** — `/nutritionists` (`PublicNutritionistLive.Index`): SEO
  `ItemList`, city + free-text filter driving local-intent queries
  ("nutritionist Rethymno").
- **Recruitment CTAs** — the public directory, profiles, and the consumer
  proof-engine pages (`/foods`, `/foods/:slug`) carry a
  `nutritionist_recruit_cta` component inviting professionals into the Pro
  pitch (hidden for existing pros).
- **Scientific articles** — `/nutritionists/:slug/articles/:article_slug`
  (public) authored at `/nutritionist/articles` (draft → published, per-paragraph
  images + references to PubMed studies / food species / compounds / diseases).
  See [`professionals/articles.md`](professionals/articles.md).

Design + honest-preview rules (no fabricated metrics): [`professionals/professional_profiles.md`](professionals/professional_profiles.md).
Booking/ICS flow: [`professionals/appointments_booking.md`](professionals/appointments_booking.md).

## 2. Run the practice (workspace)

- **Dashboard** — `/nutritionist` (`NutritionistLive.Dashboard`): stat tiles
  (active clients, pending invitations, upcoming appointments, blueprints) plus
  an **activation checklist** (create profile → publish → first client → first
  blueprint) that self-ticks until the practice is set up.
- **Clients / records** — `/nutritionist/clients` (`NutritionistLive.Clients`):
  the unified roster, record list, and record editor. A client is a
  nutritionist-owned "patient file" (`ProfessionalClient` + `ClientIntake` +
  `ConsultationNote`) **always linked to a platform `User`**, created by CSV
  import (`DietaryHistory.{CsvParser,Importer}`) or by hand. Per-client calendar
  at `/nutritionist/clients/:id/calendar`. See [`professionals/client_records.md`](professionals/client_records.md).
- **Invitations** — `/nutritionist/invitations` (`NutritionistLive.Invitations`):
  invite a client by email **or** by name-search (reaches OAuth users whose only
  email is a synthetic placeholder).
- **Appointments** — `/nutritionist/appointments`
  (`NutritionistLive.AppointmentCalendar`): accept/manage bookings; accepted
  requests send an email + `.ics` invite.
- **Payouts** — Stripe Connect onboarding from the profile editor (authorize /
  capture lifecycle, 5% platform fee, `professional_payments` ledger). See
  [`payments/nutritionist_payments_stripe_connect.md`](../implementation/professionals/payments/nutritionist_payments_stripe_connect.md).
- **Health conditions** — `/nutritionist/conditions` (`live_session
  :nutritionist_conditions`): condition→compound dietary-advice pages, mounted
  **only** inside the gated panel. Deliberately **not** public (YMYL boundary —
  see `product_foundation.md` principle 4 and `CLAUDE.md` Health context).
  **Unlinked from the nutritionist sidebar** — the "Health" nav item was removed
  as a half-baked feature. The routes still resolve by direct URL but are no
  longer surfaced in navigation until the feature is finished; restore it by
  re-adding the `nutritionist_link` in `layout_view.ex` (`nutritionist_sidebar/1`).

## 3. Do the busywork (AI leverage)

- **Meal-plan blueprints** — `/nutritionist/blueprints` (`MealBlueprintLive`):
  author reusable meal-plan templates, AI-drafted and nutritionist-approved,
  assignable to clients.
- **AI drafting principle** — AI *drafts*; the nutritionist reviews, adjusts, and
  approves. The assistant never sends advice to a client on its own
  (`product_foundation.md` principle 1). Agents: `AI.Agents.{MealPlanAgent,
  NutritionistAgent}`. Quotas: Pro tier = 30 AI recipes / 10 meal plans per
  month.
- **Exact nutrition moat** — every recipe/meal is computed from real USDA
  FoodData Central ingredients → full 168-nutrient profile per serving
  (calculated, not estimated). This is the professional-credibility
  differentiator; see `product_foundation.md` → *The differentiator*.

---

## Route map (nutritionist-facing)

| Path | Module | Surface |
|---|---|---|
| `/nutritionist` | `NutritionistLive.Dashboard` | workspace home |
| `/nutritionist/profile` | `NutritionistLive.ProfileEdit` | profile + availability + Stripe |
| `/nutritionist/clients[...]` | `NutritionistLive.{Clients,ClientDetail,ClientCalendar,ClientRecord,ClientRecordEditor}` | roster / records / per-client calendar |
| `/nutritionist/invitations` | `NutritionistLive.Invitations` | invite clients (email / name search) |
| `/nutritionist/appointments` | `NutritionistLive.AppointmentCalendar` | bookings |
| `/nutritionist/articles[...]` | `NutritionistLive.{Articles,ArticleEditor}` | authoring |
| `/nutritionist/blueprints[...]` | `MealBlueprintLive.{Index,Editor}` | meal-plan templates |
| `/nutritionist/conditions[...]` | `HealthLive`, `ConditionDetailLive` | gated condition advice — **unlinked from nav** (half-baked) |
| `/nutritionists`, `/nutritionists/:slug` | `PublicNutritionistLive.{Index,Show}` | public directory + profile |
| `/nutritionists/:slug/articles/:article_slug` | `PublicNutritionistLive.Article` | public article |
| `/upgrade` | `UpgradeLive.Index` | become Pro |

Domain context: `Mehungry.Professionals` (facade over profiles, invitations,
assignments, appointments, ratings, articles, client records).

## Related docs

- **[`product_foundation.md`](product_foundation.md)** — purpose, audience,
  positioning, and the non-negotiable principles every feature above serves.
- [`professionals/professional_profiles.md`](professionals/professional_profiles.md) — profile + directory + nutritionist-led landing.
- [`professionals/appointments_booking.md`](professionals/appointments_booking.md) — booking + ICS.
- [`professionals/articles.md`](professionals/articles.md) — scientific articles.
- [`professionals/client_records.md`](professionals/client_records.md) — client records / dietary history.
- [`payments/nutritionist_payments_stripe_connect.md`](../implementation/professionals/payments/nutritionist_payments_stripe_connect.md) — payouts.
- [`subscriptions_billing.md`](subscriptions_billing.md) — tiers + quota enforcement.
