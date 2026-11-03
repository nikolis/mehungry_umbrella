# Nutritionist ← Client Payments (Stripe Connect) — Assessment & Minimal Build

**Status:** foundation built (Connect onboarding + status). Charging clients for a
booking is **designed here** and is the next increment — not yet built.

> **See also:** `nutritionist_payments_build_plan.md` — the full build plan for the
> charging layer **plus the compliance/obligations document** (KYC, dispute &
> negative-balance liability, SCA, VAT, acceptable-use, GDPR). Read that before
> building charging or going live.

This document assesses using Stripe to move money **from a client to a professional
nutritionist** for a paid consultation, and records the minimal slice already in the
codebase.

## 1. Why this is different from today's billing

The existing integration (`docs/subscriptions_billing.md`, `Mehungry.Billing.StripeHandler`)
is **single-party**: the platform charges its own users a SaaS subscription. Money flows
`user → M3Hungry`. It uses `mode: "subscription"` Checkout over raw HTTPoison — no SDK, no
Connect.

Paying a nutritionist is **multi-party** (a marketplace flow): money flows
`client → nutritionist`, with M3Hungry as the platform optionally taking a fee. That
requires **Stripe Connect** — the nutritionist needs a *connected account* that can receive
funds and clear KYC.

## 2. Recommended shape

- **Account type: Express.** Stripe hosts onboarding + a payouts dashboard; we own the UX
  around it. (Standard = nutritionist manages a full Stripe dashboard; more than we need.
  Custom = we own all UI + compliance; too much.)
- **Charge type: destination charge with `application_fee_amount`.** The client is charged on
  the platform; funds (minus our fee) are transferred to the nutritionist's connected
  account via `payment_intent_data[transfer_data][destination]`. This keeps the client's
  card relationship with M3Hungry (better trust for local bookings) and lets us take a
  platform fee in one call. The alternative (separate charges + transfers) is only needed if
  a single payment must split across multiple nutritionists — not our case.
- **Timing: authorize on request, capture on accept.** Appointments are **accept-first**
  (see `docs/professionals/appointments_booking.md`). Charging before the nutritionist
  accepts is wrong. Two options:
  1. **Capture-later PaymentIntent** — create the PaymentIntent with
     `capture_method: manual` when the client requests; capture it in `accept_appointment/1`;
     cancel it on decline/expiry. Card is authorized (held) but not charged until acceptance.
     Auth holds expire after ~7 days, which fits a booking horizon.
  2. **Charge on accept** — only create the Checkout Session/PaymentIntent once the
     nutritionist accepts, emailing the client a pay link. Simpler, but the slot isn't
     financially guaranteed at request time.

  Recommend **(1)** for the best UX once we build charging.

## 3. What's built now (the minimal slice)

Onboarding only — enough for a nutritionist to become payable, with no charging yet:

- **Schema** (`professional_profiles`): `stripe_connect_account_id`, `stripe_charges_enabled`,
  `consultation_fee_cents`.
- **`Billing.StripeHandler`** (account lifecycle has **both v1 and v2** implementations, selected by
  `config :mehungry, :stripe_accounts_api`, **default `:v1`** — see `go_live_runbook.md` §1):
  - `create_connect_account/1` — **v1** (default): `POST /v1/accounts` (Express, requests
    `transfers` + `card_payments`). **v2**: `POST /v2/core/accounts` requesting
    `configuration.merchant.card_payments` **and** `configuration.recipient.stripe_balance.stripe_transfers`
    (both, because we keep `on_behalf_of` with the nutritionist as merchant of record; platform owns
    fees/losses).
  - `create_account_link/3` — **v1**: `POST /v1/account_links`. **v2**: `POST /v2/core/account_links`
    (`use_case.account_onboarding`, `collection_options.fields: eventually_due`).
  - `get_connect_account/1` — **v1**: reads `charges_enabled`. **v2**: derives `charges_enabled` from
    **both** the merchant `card_payments` and recipient `stripe_transfers` capability statuses = `active`.
  - `create_login_link/1` → v1 `login_links` (same for both; works for v1 + v2 Express accounts).
  - Webhook (toggle-independent): v1 `account.updated` → `set_stripe_charges_enabled/2`; v2 thin
    `v2.core.account[...].capability_status_updated` → `related_object.id` →
    `Professionals.sync_stripe_account_status/1` (re-fetch + recompute). Both clauses are always live.
- **UI**: `/nutritionist/profile` → "Connect payouts with Stripe" starts onboarding;
  Stripe returns to `/nutritionist/profile?stripe=return`, which re-syncs status. A green
  "Payouts connected" badge shows when `charges_enabled`.

## 4. What's NOT built yet (next increment)

- A paid-booking path: manual-capture PaymentIntent on request → capture on accept → cancel
  on decline. Needs `consultation_fee_cents` to be set, `stripe_charges_enabled == true`, and
  new webhook handling (`payment_intent.succeeded`, `.canceled`, `charge.refunded`).
- Refund/no-show policy (full refund on decline is automatic if we only capture on accept;
  cancellation windows are a product decision).
- **Stripe Tax** for VAT/GST on consultations (registration per nutritionist jurisdiction).
- Payout schedule / negative-balance handling / dispute liability (Express defaults are
  reasonable; revisit before launch).

## 5. Effort & risk

- **Onboarding (done):** ~0.5 day. Low risk; no money moves.
- **Charging increment:** ~2–3 days (manual-capture lifecycle, webhooks, refunds, tests
  with Stripe test-mode Connect accounts). Medium risk — money movement + KYC edge cases
  (nutritionist not fully onboarded, capability pending, currency mismatch). Gate the "book"
  button on `stripe_charges_enabled` and a set fee.
- **Config:** reuse `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET`. Add the `account.updated`
  (and later `payment_intent.*`) events to the webhook endpoint in the Stripe dashboard.

## 6. Verification (test mode)

Connect onboarding: click "Connect payouts", complete the Express onboarding with Stripe
test data, confirm the browser returns to `/nutritionist/profile?stripe=return` and the badge
flips to connected; confirm `account.updated` also flips it via webhook. Use
`stripe listen --forward-to /webhooks/stripe` locally.

## 7. Reporting over the ledger

The nutritionist **Earnings & pipeline** page (`/nutritionist/analytics`) reads this ledger —
never Stripe — for all revenue figures. Net is the single shared formula
`amount_cents − platform_fee_cents − refunded_amount_cents` over `paid`/`partially_refunded`
rows, identical to `AppointmentPayment.net_cents/1`, so a dashboard total can never drift from
the ledger. The SQL-aggregate functions live in `Mehungry.Professionals`:
`net_earnings_cents/2`, `in_flight_cents/1`, `count_pending_requests/1`, `revenue_per_period/3`,
`appointments_per_week/2`, `revenue_by_service/2`, `revenue_by_outcome/2`,
`revenue_new_vs_returning/2`. See `docs/features/professionals/analytics.md`.
