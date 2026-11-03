# Consultation Payments — Go-Live Runbook

**Status:** feature built + verified live in test-mode (2026-11-02); flag-gated **off** in prod
(`:consultation_payments_enabled`). This doc is the ordered path from "built" to "charging real
clients." Companion to `nutritionist_payments_build_plan.md` (the build + obligations) and
`nutritionist_payments_stripe_connect.md`.

The four tracks below are **independent and parallelisable**; only §4 (the flag flip) is gated on
all of them.

---

## 1. Accounts v1 → v2 migration plan

> **Status (2026-11-03): v2 code DONE, but behind a toggle defaulting to v1.** The account
> lifecycle (`Billing.StripeHandler.create_connect_account/1`, `create_account_link/3`,
> `get_connect_account/1`) now has **both** a v1 and a v2 implementation, selected by
> `config :mehungry, :stripe_accounts_api` (**default `:v1`**). **Launch on `:v1`** — the
> stable, live-verified path (requires "Accounts v1 support" enabled in the Stripe dashboard).
> Flip the toggle to `:v2` once Accounts v2 is GA; the v2 path runs on `/v2/core/*` (JSON body,
> `Stripe-Version` preview header pinned in `:stripe_accounts_api_version` = `2026-10-28.preview`).
> The webhook handles **both** v1 `account.updated` and v2 `capability_status_updated` regardless
> of the toggle. **Owner decision (2026-11-03): don't launch real money on the v2 preview API —
> launch on v1, keep v2 as the GA fast-follow.**
> **Decision (owner, 2026-11-03):** we **keep `on_behalf_of`** (nutritionist is
> merchant of record, bears Stripe fees, their name on receipts, full 5% stays
> net), so each account requests **both** `configuration.merchant`
> (`card_payments`) **and** `configuration.recipient`
> (`stripe_balance.stripe_transfers`). Money movement (Checkout/capture/cancel/
> refund) is unchanged. `create_login_link/1` stays on the v1 `login_links`
> endpoint (shared account id; works for v2 Express accounts). What's left before
> this track is "launch-ready" is **operational**: still verify in a fresh sandbox
> with *Accounts v1 support OFF* (so the test proves v2), and decide whether to
> stay on the pinned preview version for live money or wait for v2 GA (see the
> caveat below). The v1 `account.updated` webhook clause is kept alongside the v2
> one during transition.

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

### What actually changed (v1 → v2) — scoped to our `Billing.StripeHandler` (DONE)
| Area | v1 (before) | v2 (now, shipped) |
|---|---|---|
| Base/path | `POST /v1/accounts` (form-encoded) | `POST /v2/core/accounts` — **JSON body** + `Stripe-Version: 2026-10-28.preview` header (`post_v2/2` helper) |
| Account shape | flat `business_profile[...]`, `capabilities[...]` | nested `configuration.merchant.capabilities.card_payments` **and** `configuration.recipient.capabilities.stripe_balance.stripe_transfers` + `identity.country` + `dashboard: express` + `defaults.responsibilities.{fees,losses}_collector: application` |
| Onboarding link | `POST /v1/account_links` (`type: account_onboarding`) | `POST /v2/core/account_links` with `use_case.account_onboarding.{refresh_url,return_url,collection_options.fields: eventually_due}` |
| Status read (`get_connect_account/1`) | `account["charges_enabled"] / details_submitted / payouts_enabled` | `GET /v2/core/accounts/:id?include=configuration.merchant&…recipient&…requirements`; `charges_enabled` ⇔ **both** `merchant…card_payments.status` **and** `recipient…stripe_transfers.status` = `active` |
| Login link | `POST /v1/accounts/:id/login_links` | **unchanged** — v1 `login_links` works for v2 Express accounts (shared `acct_…` id) |
| account webhook | `account.updated` → `account["charges_enabled"]` | thin `v2.core.account[...].capability_status_updated` (merchant/recipient) + `[requirements].updated` → `related_object.id` → re-fetch + recompute via `Professionals.sync_stripe_account_status/1`. v1 clause kept during transition. |
| `account.application.deauthorized` | `event["account"]` | left as-is — platform-created Express/recipient accounts don't user-deauthorize; no v2 equivalent needed |
| **Charging flow** (Checkout session, PI capture/cancel, refunds, `transfer_data[destination]` + `on_behalf_of` + `application_fee_amount`) | — | **unchanged** — references the connected account id, not Accounts-version-specific. `on_behalf_of` is **kept** (nutritionist = MoR), which is why both merchant + recipient configs are requested |

**Key insight (held):** the migration stayed contained to the **account lifecycle**
(`create_connect_account/1`, `create_account_link/3`, `get_connect_account/1`, the account webhook
clause + the new `Professionals.sync_stripe_account_status/1`). The money-movement half is untouched.

### Steps — all code steps ✅ done (2026-11-03)
1. ✅ v2 HTTP layer: `post_v2/2` (JSON) + `get_v2/1` + `Stripe-Version` header; `:stripe_accounts_api_version` config. Subscriptions stay on the v1 form-encoded path.
2. ✅ `create_connect_account/1` → `POST /v2/core/accounts` with merchant (`card_payments`) + recipient (`stripe_transfers`) configs, `identity.country` (`:connect_account_country`, default `GR`), express dashboard, application fees/losses. Optional `:connect_account_mcc` nested under merchant.
3. ✅ `get_connect_account/1` reads the two v2 capability statuses; stored `stripe_charges_enabled` keeps "can be charged onto now" semantics (needs both active).
4. ✅ Onboarding link → `POST /v2/core/account_links`. Login link kept on v1 (works for v2 Express).
5. ✅ v2 `capability_status_updated` webhook clause → `Professionals.sync_stripe_account_status/1` (re-fetch, not inline); v1 `account.updated` kept during transition.
6. ✅ MCC/classification: industry chosen at onboarding; `business_profile` product/url **not** sent on v2 create (field shape differs) — config retained as reference.
7. ⏳ **Operational, not done:** verify in a **fresh sandbox with Accounts v1 support OFF** (so the test proves v2), re-running the full test-mode flow (onboard → book → authorize → capture → refund).
8. ✅ `stripe_handler_test.exs` covers v2 `capability_status_updated` dispatch (stubbed `get_connect_account`); `StripePaymentClientStub` gained `get_connect_account/1`.

### Caveat before live money
The pinned `2026-10-28.preview` version is a **preview** API. Moving real money on a preview version
is the one remaining judgement call: either accept the pin (it's isolated to the account-lifecycle
calls — money movement is on stable endpoints) or wait for Accounts v2 GA and bump the version string.
The §1 alternative — launch on **Accounts v1 support** and keep this v2 code dark — is also still open,
since the v1 `account.updated` clause remains.

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

**Where it's surfaced — WIRED 2026-11-03** (owner to review final wording; copy lives in the app now):
1. ✅ **Terms** (`terms_html/index.html.heex`, §6 Nutritionist marketplace) — a "Consultation
   bookings — cancellation & refunds" subsection carrying the copy above.
2. ✅ **At the paid-booking step** — a one-line summary + Terms link in the booking modal
   (`PublicNutritionistLive.Show`, Step-3 confirm form), shown only when payments are live
   (`:consultation_payments_enabled`) **and** a priced service is selected. The thresholds are
   **interpolated from config** (`Professionals.free_cancel_hours/0`, `partial_refund_hours/0`) so
   this surface can never drift from the refund logic. Test:
   `public_nutritionist_live_test.exs` "cancellation-policy notice shows at the paid-booking confirm step".
3. ⏭️ Standalone `/refund-policy` page — **skipped** (the Terms subsection + in-flow notice cover it;
   add later if a footer link is wanted).

The Terms thresholds are plain text with a sync comment pointing at the config keys. If you change
`:consultation_free_cancel_hours` / `:consultation_partial_refund_hours`, update the Terms copy (the
booking-modal copy updates itself).

> Keep the thresholds in the copy in sync with the config keys
> (`:consultation_free_cancel_hours`, `:consultation_partial_refund_hours`). If you change the
> config, change the copy.

### 3b. Privacy policy — Stripe is **already** a listed sub-processor (§5)
`privacy_policy_live.ex` already lists Stripe under "Who we share data with" and under
international transfers (§6). For consultation payments we only need to **extend the Stripe line**
to cover: (a) connected-account onboarding data for nutritionists (identity/bank — collected by
Stripe, not us), and (b) client payment data for bookings. (This edit is made alongside this doc.)
No new sub-processor; card data still never touches our servers (PCI SAQ A).

### 3c. VAT invoicing (accountant — deferred to first income)
The 5% commission is **VAT-inclusive** (decided). Still to finalise with the accountant: the
**invoicing mechanism** for the commission (manual/myDATA vs Stripe Tax/Invoicing), cadence, and
EU cross-border reverse charge. The ledger already records `fee_vat_cents` per row.

> **Owner decision (2026-11-03):** this is **deferred to first income**. Platform commission income
> is currently **€0**, so no commission invoice is yet due; the obligation only bites when the first
> paid booking settles. The invoicing mechanism **must be agreed with the accountant before the first
> paid booking**, not before flipping the flag technically. A ready-to-send brief for the accountant
> is in `accountant_commission_invoicing_note.md`.

---

## 4. Go-live: flip the flag

**Hard prerequisites before the flag goes true** (§3c is the one that's been deferred — see below):

- **§2 done** — prod Connect enabled + webhook endpoint registered (live mode). Without the prod
  webhook endpoint the charge flow silently breaks: holds never capture, capability status never
  syncs. This is **owner dashboard work** and cannot be skipped.
- **§1 — launch on v1** (`:stripe_accounts_api = :v1`, the default). This is the live-verified path;
  just enable **"Accounts v1 support"** in the Stripe dashboard. The v2 path stays dark until
  Accounts v2 is GA, at which point flip the toggle to `:v2` and re-run the sandbox verify. (No need
  to accept preview-API risk for live money.)
- **§3a/§3b published** — ✅ done.
- **§3c — deferred to first income** (owner decision 2026-11-03): the flag may flip before the
  commission-invoicing mechanism is set, because income is €0 and no invoice is yet due — but the
  mechanism **must be agreed with the accountant before the first paid booking settles**.

Then:

1. Final **test-mode** pass green (onboard → book → authorize → capture → decline → refund tiers).
2. Set prod config **`:consultation_payments_enabled = true`** (prod `config/runtime.exs` or the
   prod config path — **not** `config/dev.exs`, which is the dev-only switch) and deploy.
3. **Prod smoke test** (§2 "Verify") — one real low-value live booking + refund with your own card.
4. Announce to nutritionists: connect payouts on `/nutritionist/payments`, pick **Health &
   Wellness Coaching** at Stripe onboarding, set their service prices.
5. **Watch for the first paid booking** → that's the trigger to have the accountant's invoicing
   mechanism live (§3c).

### Rollback
Flip `:consultation_payments_enabled` back to `false` and deploy — booking instantly reverts to
request-only (no charge), prices become display-only. In-flight authorized holds expire on Stripe
(~7 days) or are released by `AppointmentHoldExpiryWorker`. No data migration needed either way.

---

## Checklist

- [x] **§1** v2 code shipped behind `:stripe_accounts_api` toggle (default `:v1`). **Launch on v1** — enable "Accounts v1 support" in the Stripe dashboard. v2 is the GA fast-follow (flip toggle + sandbox-verify then).
- [ ] **§2** Enable Connect + platform profile/branding/support; confirm `debit_negative_balances`
- [ ] **§2** Register webhook endpoint + events on `https://www.m3hungry.com/webhooks/stripe`; set `STRIPE_WEBHOOK_SECRET`
- [x] **§3a** Refund copy wired into Terms + booking step (2026-11-03) — ⏳ owner reviews final wording
- [ ] **§3b** Extend Stripe sub-processor line in privacy policy *(done with this doc)*
- [~] **§3c** Commission-invoicing mechanism — **deferred to first income** (income €0 now); brief drafted (`accountant_commission_invoicing_note.md`); agree with accountant **before the first paid booking**
- [ ] **§4** Flip `:consultation_payments_enabled` in prod + smoke test
