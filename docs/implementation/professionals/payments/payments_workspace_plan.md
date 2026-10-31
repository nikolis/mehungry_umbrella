# Nutritionist Payments Workspace — Feature Plan

**Status:** **Phases A–B built & tested (2026-10-31).**
- **A:** `professional_services` table + `Mehungry.Professionals.ProfessionalService` schema
  (+ `price_eur` virtual) + the appointment `professional_service_id` link + context CRUD
  (`list_services`, `list_active_services`, `create/update/archive/delete_service`,
  `ensure_intro_service`). Tests: `professional_services_test.exs` (10).
- **B:** `/nutritionist/payments` route + `MehungryWeb.NutritionistLive.Payments` (Stripe
  onboarding moved here from the profile editor; services/packages CRUD UI; locked-intro row;
  obligation banner), a **"Payments"** nav entry in `main_menu.html.heex`, and the profile
  editor's payments section replaced by a pointer. Tests: `payments_test.exs` (4). The badge
  is still **binary** here — Phase C upgrades it to the multi-state machine.

Phases C–E below are still planning. Scope: a dedicated **Payments** workspace for
nutritionists —
its own menu entry + LiveView — carrying (1) guided Stripe Connect onboarding with a
**trustworthy, multi-state** status badge, (2) a **service-pricing model** (per-session
services **and** package deals), and (3) the **free 15-minute intro session** obligation.

Companion to `nutritionist_payments_build_plan.md` (the charging layer) and
`nutritionist_payments_stripe_connect.md` (the onboarding assessment). **This feature is
the UI + data model the charging layer prices against** — see §7 for the dependency.

---

## 1. Why — the gap this closes

Today (mainline): payments is a **sub-section buried in the profile editor**
(`profile_edit.ex:399-432`) with **one** `consultation_fee_eur` field and a **binary**
"Payouts connected" badge. There is no packages concept, no free-intro concept, no
dedicated page, and **zero test coverage** for any of it. The badge is a single boolean
(`stripe_charges_enabled`) that can't express the most common real onboarding state —
"submitted, pending Stripe verification". This plan replaces that with a real workspace.

Measured against the competitor (`diatrofologos-online.gr`): they sell a free 15-min intro,
a €40 initial, €30 follow-ups, and a €130 package (1 initial + 4 follow-ups). Our model must
express exactly that shape.

---

## 2. Data model

### 2.1 New table `professional_services`

One row per offering a nutritionist sells (or the locked free intro).

| Column | Type | Notes |
|---|---|---|
| `id` | id | |
| `professional_id` | FK → `users` | the nutritionist (matches how `Appointment.professional` is keyed) |
| `kind` | string | `"intro"` \| `"session"` \| `"package"` |
| `name` | string | e.g. "Initial consultation", "2-month support" |
| `description` | text | free text — a package lists its composition here in v1 |
| `price_cents` | integer | `0` for intro; stored in cents (matches existing convention) |
| `currency` | string | default `"eur"` |
| `duration_minutes` | integer | session length; `15` and locked for intro; nil allowed for packages |
| `session_count` | integer | packages: number of sessions included (e.g. 5); 1 for a session |
| `active` | boolean | soft-hide without deleting (keeps historical appointments valid) |
| `position` | integer | display order |
| timestamps | | |

**Schema module:** `Mehungry.Professionals.ProfessionalService` with
`changeset/2` (nutritionist-editable) + validations (`price_cents >= 0`,
`kind` inclusion, intro is `price_cents == 0 and duration_minutes == 15`).

**The free intro is a reserved, system-managed row.** On profile creation (and lazily on
first Payments-page load) we **seed exactly one `kind: "intro"` service** per profile,
price 0 / 15 min, that the nutritionist **cannot delete or re-price** (they may edit its
name/description only). This keeps all booking + pricing logic uniform — every appointment
points at a service, intro included — and makes "you are obliged to offer a free 15-min
intro" a structural guarantee, not a convention.

> **v1 package model is deliberately flat** (name + total price + `session_count` +
> description). A richer model (a `professional_service_components` join: "this package =
> 1× Initial + 4× Follow-up", auto-decrementing as sessions are booked) is a **future**
> option noted in §8 — not v1.

### 2.2 Appointment linkage

Add to `professional_appointments`:

| Column | Type | Notes |
|---|---|---|
| `professional_service_id` | FK → `professional_services`, nullable | which service this booking is for |

Nullable so the 59-commit-old free-request appointments still validate. New bookings set it.
`request_appointment/4` derives `title`, duration (`ends_at`), and — once charging lands —
price from the chosen service instead of the profile's single fee. Intro bookings carry the
intro service → always free, never charged.

### 2.3 Profile schema changes

- **Keep `consultation_fee_cents`/`consultation_fee_eur` for now** (don't break the charging
  branch mid-flight), but **stop surfacing it** in the profile editor — the services table
  supersedes it. Plan a follow-up migration to drop it once the charging branch is rebased
  to read `ProfessionalService.price_cents` (§7).
- **Add richer Stripe status fields** (badge reliability, §4):
  - `stripe_details_submitted` boolean, default false
  - `stripe_payouts_enabled` boolean, default false
  - `stripe_requirements_due` boolean, default false  *(true when Stripe lists
    `currently_due`/`past_due` requirements — i.e. "action needed")*
  - (`stripe_charges_enabled` already exists)

---

## 3. The Payments LiveView (`/nutritionist/payments`)

New route in the `:nutritionist` live_session + new module
`MehungryWeb.NutritionistLive.Payments`. Three stacked sections:

### 3.1 Stripe onboarding card (multi-state — §4)
Shows the current status badge + the one contextual action for that state. Replaces the
single "Connect payouts" button.

### 3.2 Services & pricing
- A list of the nutritionist's services (sessions + packages), each with name, price,
  duration/session-count, active toggle, edit, archive. Reorder via `position`.
- "Add session" / "Add package" buttons → inline form (core_components modal, the preferred
  pattern) using `ProfessionalService.changeset/2`.
- The **intro row is pinned at top, labelled "Free intro (required)"**, price/duration locked,
  only name/description editable.

### 3.3 Free-intro obligation notice
A fixed informational banner (not a toggle): *"Every nutritionist on the platform offers a
free 15-minute introductory session. Clients can request one from your public profile; you
accept or decline like any booking. This can't be turned off."* Ties the structural guarantee
(§2.1) to an explicit, visible statement so the obligation is understood.

### 3.4 Menu entry
Add a **"Payments"** item to the "Your practice" block in
`views/layout/templates/menu/main_menu.html.heex` (after "Appointments", before the divider),
`href="/nutritionist/payments"`, icon `hero-banknotes` (or `hero-credit-card`). Remove the
payments sub-section from `profile_edit.ex` (leave a one-line pointer linking to the new page).

---

## 4. The reliable, multi-state badge

### 4.1 Status derivation — `Professionals.stripe_status/1`
A pure function over the persisted Stripe fields returning one atom:

| Status | Condition | Badge | Action offered |
|---|---|---|---|
| `:not_started` | no `stripe_connect_account_id` | grey "Not set up" | **Set up payments** |
| `:pending` | account exists, `details_submitted` **false** | amber "Finish setup" | **Continue setup** |
| `:restricted` | `details_submitted` true but `requirements_due` true (Stripe needs more) | amber "Action needed" | **Resolve with Stripe** |
| `:active` | `charges_enabled` true | green "Accepting payments" | (manage link) |
| `:disabled` | was active, now `charges_enabled` false & requirements due | red "Payments paused" | **Resolve with Stripe** |

This fixes the three mainline reliability gaps: (a) the common "submitted, pending"
state is now visible; (b) the label reflects **charges** ("Accepting payments"), not
"payouts"; (c) "action needed" is surfaced instead of silently re-showing a "Connect" button.

### 4.2 Keeping it sourced from Stripe (both paths persist **all** fields)
- Extend `StripeHandler.get_connect_account/1` to already-returned
  `charges_enabled`/`details_submitted`/`payouts_enabled` **plus** a derived
  `requirements_due` (non-empty `requirements.currently_due`/`past_due`).
- `maybe_sync_stripe` (on `?stripe=return`) persists **all four** fields, not just
  `charges_enabled`.
- Webhook `account.updated` → extend `set_stripe_charges_enabled/2` into
  `sync_stripe_account/2` that writes all four from the event payload.
- **Ops note (enforced in the doc, not code):** `account.updated` must be registered on the
  Stripe endpoint or the badge only refreshes on profile revisit. Already called out in
  `nutritionist_payments_build_plan.md` §5.

---

## 5. Public profile + booking changes

`PublicNutritionistLive.Show` + its booking wizard (`show.ex`):

- **Render the service menu**: sessions and packages with prices + durations, and a
  prominent **"Book a free 15-min intro"** CTA (the intro service).
- **Booking wizard gains a first step: pick a service** → then day → time → confirm. The
  chosen `service_id` flows into `request_appointment/4` (`opts[:service_id]`), which derives
  title + duration from it.
- Intro bookings: zero-cost, no payment step ever (even after charging lands).
- Paid services: today still request-only (charging is gated behind the separate branch +
  `:consultation_payments_enabled`); the UI shows the price as information. When charging
  lands, the same `service_id` drives the PaymentIntent amount.

---

## 6. Test seam + coverage (the part that's missing today)

### 6.1 Connect test seam
Introduce a `:stripe_connect_client` behaviour seam (mirroring the subscription
`:stripe_period_end_fetcher` and the charging branch's `:stripe_payment_client`) wrapping
`create_connect_account/1`, `create_account_link/2`, `get_connect_account/1`. **Align the
naming with the charging branch** so a later merge doesn't create two seams. A test stub
records calls + returns canned account states.

### 6.2 Tests to write
- **`ProfessionalService` context**: create/update/archive; intro row auto-seeded,
  not deletable, not re-priceable; price/kind validations; ordering.
- **`stripe_status/1`**: a case per row of the §4.1 table (every field combination → expected
  status). Pure, fast, exhaustive — this is the heart of badge reliability.
- **`maybe_sync_stripe`** (LiveView test, stubbed): `?stripe=return` persists all four fields.
- **`account.updated` webhook**: persists all four fields (extends `stripe_handler_test.exs`).
- **Payments LiveView**: renders the correct badge + action per status; service CRUD
  round-trips; intro row locked; obligation banner always present.
- **Booking**: requesting an intro creates a 15-min free appointment linked to the intro
  service; requesting a paid service links the service and derives duration/title.

---

## 7. Sequencing & relationship to the charging branch

This workspace is **additive to mainline** and does **not** require the charging branch to
ship first. But the two meet at the pricing field:

1. **Land this workspace on mainline** (services model, Payments LiveView, badge, tests).
   Paid services display price but remain request-only.
2. **Rebase the charging branch** (`nutritionist_payments_build_plan.md` §3) and point its
   PaymentIntent amount at `ProfessionalService.price_cents` **instead of**
   `profile.consultation_fee_cents`. Reconcile there, then drop `consultation_fee_cents`.
3. **Flip `:consultation_payments_enabled`** after the §4 obligations (VAT, acceptable-use,
   refund policy) are done.

Doing the workspace first is the right order: it de-risks the charging rebase (the pricing
model it reads will already exist and be tested) and ships immediate user value (packages +
intro + a trustworthy badge) without waiting on the compliance gate.

---

## 8. Open decisions

1. **Package model depth** — flat (name + total + count + description) for v1, or the richer
   component model (§2.1)? *Recommend flat for v1.*
2. **Intro length** — fixed 15 min platform-wide, or nutritionist-configurable (10–20)?
   *Recommend fixed 15 to match the "obligation" framing.*
3. **Can a nutritionist opt out of paid services entirely** (free-request-only practice) and
   still be listed? *Recommend yes — services are optional; the intro is the only mandatory
   one.*
4. **Currency** — EUR-only for now, or per-service currency? *Recommend EUR-only (matches the
   Greek market and the charging branch's `eur` default).*
5. **Where the fee field dies** — drop `consultation_fee_cents` in step 7.2, or keep as a
   "default session price" shim? *Recommend drop after rebase.*

---

## 9. Effort estimate

| Phase | Work | Effort |
|---|---|---|
| A | ✅ **done** — `professional_services` + `ProfessionalService` + appointment FK + migrations + context CRUD + intro seeding + tests | ~0.5 day |
| B | ✅ **done** — Payments LiveView + menu entry + service CRUD UI + removed old sub-section + tests | ~1 day |
| C | Multi-state badge: status fields migration, `stripe_status/1`, extend sync + webhook | ~0.5–1 day |
| D | Public profile service menu + booking "pick a service" step + intro CTA | ~1 day |
| E | Connect test seam + full test suite (§6) | ~1 day |

**~4–4.5 engineering days**, independent of the compliance gate. Ships real value on mainline
before the charging branch is resurrected.

---

## 10. Cross-references

- Charging layer + obligations: `nutritionist_payments_build_plan.md`
- Onboarding assessment: `nutritionist_payments_stripe_connect.md`
- Booking lifecycle: `docs/features/professionals/appointments_booking.md`
- Current code touched: `professional_profile.ex`, `professionals.ex` (`request_appointment`),
  `live/nutritionist_live/profile_edit.ex`, `live/public_nutritionist_live/show.ex`,
  `billing/stripe_handler.ex`, `views/layout/templates/menu/main_menu.html.heex`
