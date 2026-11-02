# Consultation Payments — Go-Live Runbook

**Status:** feature built + verified live in test-mode (2026-11-02); flag-gated **off** in prod
(`:consultation_payments_enabled`). This doc is the ordered path from "built" to "charging real
clients." Companion to `nutritionist_payments_build_plan.md` (the build + obligations) and
`nutritionist_payments_stripe_connect.md`.

The four tracks below are **independent and parallelisable**; only §4 (the flag flip) is gated on
all of them.

---

## 1. Accounts v1 → v2 migration plan

### Why
Stripe now **defaults new Connect integrations to Accounts v2** (`POST /v2/core/accounts`) and
**rejects v1 account creation** in fresh sandboxes/accounts unless "Accounts v1 support" is enabled
in Dashboard → Developers → API policies. Our code is entirely **v1** (`@stripe_api =
https://api.stripe.com/v1`).

### Decision & sequencing
- **For launch:** enable **Accounts v1 support** on the prod account (one toggle) — our current
  code works unchanged, and the existing subscriptions account is older/likely grandfathered.
  This unblocks go-live **without** the migration.
- **Caveat on v2:** Accounts v2 is still delivered on **preview API versions** (e.g.
  `Stripe-Version: 2026-10-28.preview`). Shipping onto a preview version for money movement is a
  real risk. **Recommendation: launch on v1-support, migrate to v2 as a fast-follow** once v2
  leaves preview (or once we're comfortable pinning a preview version).
- Because **no live connected accounts exist yet** (pre-launch), the migration needs **no data
  backfill** — it's a pure code swap. Doing it before the first real nutritionist onboards avoids
  ever having to migrate account records.

### What actually changes (v1 → v2) — scoped to our `Billing.StripeHandler`
| Area | v1 (today) | v2 |
|---|---|---|
| Base/path | `POST /v1/accounts` | `POST /v2/core/accounts` (+ `Stripe-Version` preview header, `include[]=configuration.merchant`) |
| Account shape | flat `business_profile[...]`, `capabilities[...]` | nested `configuration.merchant.{mcc, capabilities, ...}` + `identity` + **controller** properties |
| Onboarding link | `POST /v1/account_links` | Account Links v2 / hosted onboarding (connected to the v2 account) |
| Status read (`get_connect_account/1`) | `account["charges_enabled"] / details_submitted / payouts_enabled` | read `configuration.merchant.capabilities` (e.g. `card_payments`, `transfers` = `active`) |
| Login link | `POST /v1/accounts/:id/login_links` | v2 dashboard/login equivalent |
| `account.updated` webhook | `account["charges_enabled"]` | **`v2.core.account[configuration.merchant].updated`** — different event type + payload shape |
| `account.application.deauthorized` | `event["account"]` | confirm v2 equivalent |
| **Charging flow** (Checkout session, PI capture/cancel, refunds, `transfer_data[destination]` + `on_behalf_of` + `application_fee_amount`) | — | **largely unchanged**; these reference the connected account id and are not Accounts-version-specific |

**Key insight:** the migration is contained to the **account lifecycle** (create / onboarding /
status / account webhooks) — roughly `create_connect_account/1`, `create_account_link/*`,
`get_connect_account/1`, `create_login_link/1`, and the two account webhook clauses. The
money-movement half (what we spent the most effort verifying) is untouched.

### Steps
1. Make the API version + base path configurable per call (add a `Stripe-Version` header helper;
   allow `/v2/...` paths). Keep subscriptions (`/v1/checkout`, `/v1/subscriptions`) on v1.
2. Rewrite `create_connect_account/1` → `POST /v2/core/accounts` with
   `configuration.merchant.{mcc, capabilities[card_payments][requested], capabilities[transfers][requested]}`
   + `identity` + the **controller** block (platform-controlled, Express-equivalent dashboard/fees/losses).
3. Rewrite `get_connect_account/1` to derive `charges_enabled`-equivalent from
   `configuration.merchant.capabilities` (we can keep the stored boolean `stripe_charges_enabled`
   semantics — "can be charged onto now").
4. Rewrite account onboarding link + login link to the v2 equivalents.
5. Add the `v2.core.account[configuration.merchant].updated` webhook clause → keep calling
   `Professionals.set_stripe_charges_enabled/2`; retire the v1 `account.updated` clause (or keep
   both during transition).
6. Keep `business_profile`/MCC classification intent (now `configuration.merchant.mcc`).
7. Verify in a **fresh sandbox with Accounts v1 support OFF** (so the test proves v2), re-running
   the full `go_live_runbook` §... test-mode flow (onboard → book → authorize → capture → refund).
8. Update `stripe_handler_test.exs` / stubs for the v2 shapes.

### Effort
~1–1.5 eng days (account lifecycle only), + test-mode re-verification. **Not** on the launch
critical path if v1-support is enabled.

---

## 2. Webhook endpoint + Connect dashboard setup (prod)

### Stripe dashboard (prod account, **live mode**)
1. **Enable Connect** (if not already) and complete the **platform profile** — business details,
   **branding** (name/logo/colour shown in Express onboarding + on client receipts), and **support**
   details.
2. Confirm **`debit_negative_balances`** is on for created connected accounts (dispute/refund
   recovery — build plan §4.2).
3. **Enable "Accounts v1 support"** (Developers → API policies) unless/until the §1 v2 migration ships.
4. Set the **MCC/industry** expectation for connected accounts to **Health & Wellness Coaching**
   (our `create_connect_account` already stamps `business_profile`); instruct nutritionists to pick
   that industry at onboarding.

### Webhook endpoint (Developers → Webhooks → add endpoint)
- **URL:** `https://www.m3hungry.com/webhooks/stripe`
- **Events to subscribe** (the payment flow + Connect account lifecycle):
  - `checkout.session.completed`, `checkout.session.expired`
  - `payment_intent.canceled`, `payment_intent.payment_failed`
  - `charge.refunded`, `charge.dispute.created`
  - `account.updated` (v1) **or** `v2.core.account[configuration.merchant].updated` (after §1)
  - `account.application.deauthorized`
  - *(keep the existing subscription events: `customer.subscription.updated/deleted` — same endpoint)*
- Copy the endpoint's **signing secret** → set prod env **`STRIPE_WEBHOOK_SECRET`** (Fly secret).
  Our handler verifies every event against it (`StripeHandler.verify_signature`).

### Secrets (Fly) — reuse the subscriptions account
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` already set for subscriptions — the **same platform
  account** handles Connect, so no new keys. Any new price IDs (none for consultations) via
  `fly secrets set` + redeploy.
- Config (compiled, not secrets): `:platform_fee_bps` 500, `:platform_fee_vat_bps` 2400,
  `:consultation_free_cancel_hours` 24, `:consultation_partial_refund_hours` 4,
  `:connect_product_description` / `:connect_business_url` (set), `:connect_account_mcc` (unset —
  rely on industry auto-assignment).

### Verify (live mode, carefully)
Do one **real** low-value live booking end-to-end after the flag flip (§4) with a real card you
control, then refund it — confirming the live webhook signs + delivers to prod.

---

## 3. Refund/cancellation policy (publish) + privacy

### 3a. Consumer refund & cancellation policy — **draft copy** (owner to approve)

> **Consultation bookings — cancellation & refunds**
>
> When you book a paid consultation on M3Hungry, your card is **authorised (held), not charged**,
> at the time of booking. The nutritionist must **accept** the request before any money is taken —
> if they decline, or don't respond in time, the hold is released and **you are not charged**.
>
> Once a booking is **accepted and paid**, you can cancel from **My appointments**:
> - **24 hours or more** before the appointment — **full refund**.
> - **Between 4 and 24 hours** before — **50% refund**.
> - **Less than 4 hours** before, or a **no-show** — **no refund**.
>
> If the **nutritionist cancels** an accepted appointment, you receive a **full refund** regardless
> of timing — you're never charged for an appointment the nutritionist calls off.
>
> Refunds are issued to your original payment method and typically appear within 5–10 business days
> (Stripe's processing time). M3Hungry charges the nutritionist a small platform fee; all payments
> are processed securely by Stripe — we never see or store your card number.

**Where to surface it (wire-up, after approval):**
1. **Terms** (`TermsController` template) — add a "Consultation bookings — cancellation & refunds"
   section with the above.
2. **At the paid-booking step** — a one-line summary + link in the booking modal (before Confirm):
   *"Paid bookings follow our cancellation policy: full refund ≥24h, 50% 4–24h, none under 4h.
   Your card is only charged once the nutritionist accepts."*
3. Optionally a standalone `/refund-policy` page linked from the footer.

> Keep the thresholds in the copy in sync with the config keys
> (`:consultation_free_cancel_hours`, `:consultation_partial_refund_hours`). If you change the
> config, change the copy.

### 3b. Privacy policy — Stripe is **already** a listed sub-processor (§5)
`privacy_policy_live.ex` already lists Stripe under "Who we share data with" and under
international transfers (§6). For consultation payments we only need to **extend the Stripe line**
to cover: (a) connected-account onboarding data for nutritionists (identity/bank — collected by
Stripe, not us), and (b) client payment data for bookings. (This edit is made alongside this doc.)
No new sub-processor; card data still never touches our servers (PCI SAQ A).

### 3c. VAT invoicing (accountant — outstanding)
The 5% commission is **VAT-inclusive** (decided). Still to finalise with the accountant: the
**invoicing mechanism** for the commission (manual vs Stripe Tax/Invoicing). The ledger already
records `fee_vat_cents` per row. Not code-blocking for launch, but required for compliant books.

---

## 4. Go-live: flip the flag

**Do this last, only after §2 is done and §3 is published** (and §1's v1-support toggle is on, or
the v2 migration shipped).

1. Final **test-mode** pass green (onboard → book → authorize → capture → decline → refund tiers).
2. Set prod config **`:consultation_payments_enabled = true`** (prod `config/runtime.exs` or the
   prod config path — **not** `config/dev.exs`, which is the dev-only switch) and deploy.
3. **Prod smoke test** (§2 "Verify") — one real low-value live booking + refund with your own card.
4. Announce to nutritionists: connect payouts on `/nutritionist/payments`, pick **Health &
   Wellness Coaching** at Stripe onboarding, set their service prices.

### Rollback
Flip `:consultation_payments_enabled` back to `false` and deploy — booking instantly reverts to
request-only (no charge), prices become display-only. In-flight authorized holds expire on Stripe
(~7 days) or are released by `AppointmentHoldExpiryWorker`. No data migration needed either way.

---

## Checklist

- [ ] **§1** Enable Accounts v1 support on prod **or** ship v2 migration
- [ ] **§2** Enable Connect + platform profile/branding/support; confirm `debit_negative_balances`
- [ ] **§2** Register webhook endpoint + events on `https://www.m3hungry.com/webhooks/stripe`; set `STRIPE_WEBHOOK_SECRET`
- [ ] **§3a** Owner approves refund copy → wire into Terms + booking step
- [ ] **§3b** Extend Stripe sub-processor line in privacy policy *(done with this doc)*
- [ ] **§3c** Accountant confirms commission-invoicing mechanism
- [ ] **§4** Flip `:consultation_payments_enabled` in prod + smoke test
