# Direct Nutritionist Payments via Stripe Connect — Build Plan & Obligations

**Status:** planning. Companion to `nutritionist_payments_stripe_connect.md` (the
onboarding-slice assessment) and `payments_workspace_plan.md` (the Payments workspace UI +
service/package pricing model + multi-state badge this charging layer prices against — build
that **first**; see §3 Step 1 and that doc's §7).

**The important finding up front:** the charging layer we need **was already built** — in
Sept 2026, on the branch `new_professional_nutritionist_features` (single commit
`5d91fde5`). It was **never merged**, is now **59 commits behind master**, and is flag-gated
off. So this is **not a greenfield build** — it is a *resurrect-rebase-modernize-and-
go-live* job, plus the compliance prerequisites that were never done.

**Audience:** engineering (the merge/modernize work in §3) **and** the business owner (the
obligations in §4 — several are prerequisites to going live, not code).

---

## 0. TL;DR

- Goal: a client pays a nutritionist for a consultation **through M3Hungry**, we take a
  small platform fee.
- Architecture (already implemented on the branch, and it's the right shape): **Stripe
  Connect**, **Express** accounts, **destination charge + `application_fee_amount`**, with
  **manual capture** (authorize on request → capture on accept → cancel on decline), and
  `on_behalf_of` = the nutritionist (so the nutritionist is the **settlement merchant of
  record**; Stripe's processing fee comes out of their 95%).
- **What's actually left is mostly non-code:** rebase a stale branch over 59 commits of
  drift, modernize two stale assumptions (AWS→Fly.io/Supabase; fee stored in cents vs. the
  euros field master now has), flip the feature flag, and — critically — **do the compliance
  groundwork that was deferred** (VAT on our fee, dispute-liability awareness, acceptable-use
  confirmation, refund policy, GDPR disclosure).
- **KYC: handled by Stripe, not us** (the reason to use Express). But we inherit
  **dispute/negative-balance liability**, **SCA**, **VAT-on-commission**, and **GDPR**
  duties — see §4.

---

## 1. Where we actually are (ground truth, verified 2026-10-29)

### 1.1 On master / the current branch — onboarding only

| Piece | State on mainline |
|---|---|
| `professional_profiles.stripe_connect_account_id` / `stripe_charges_enabled` / `consultation_fee_cents` **+ virtual `consultation_fee_eur`** (euros in the form) | ✅ `20260902000001_extend_professional_profiles.exs` |
| `Billing.StripeHandler`: `create_connect_account/1`, `create_account_link/2`, `get_connect_account/1` | ✅ |
| Webhook `account.updated` → `Professionals.set_stripe_charges_enabled/2` | ✅ |
| `/nutritionist/profile` connect-payouts button + connected badge | ✅ |
| **Any charging path / ledger** | ❌ absent on master and on `deploy-ingredient-search-plural` |

### 1.2 On branch `new_professional_nutritionist_features` (`5d91fde5`) — the whole charging layer

Fully built and test-covered, but **unmerged, 59 commits stale, and shadowed off** behind
`:consultation_payments_enabled` (default `false`). Contents:

- **`Billing.StripeHandler`** charging calls (idempotency-keyed):
  `create_consultation_checkout/1` (Checkout `mode: payment`,
  `payment_intent_data[capture_method]=manual`, `transfer_data[destination]`,
  **`on_behalf_of`** = connected account, `application_fee_amount`),
  `capture_payment_intent/1`, `cancel_payment_intent/1`,
  `refund_payment/2` (`refund_application_fee=true`, reverses transfer).
- **Ledger:** `professional_payments` table + `Professionals.AppointmentPayment`
  (`20260919000002_create_professional_payments.exs`), one per appointment,
  `has_one :payment` on `Appointment`; status `pending→authorized→paid→refunded/
  partially_refunded` + `canceled`/`failed`; money fields are snapshots.
- **Lifecycle** (`Professionals`): `request_appointment/4` returns `{:ok, appt, checkout_url}`
  on a payable profile (`ProfessionalProfile.payable?/1` = onboarding done + fee > 0), else
  the free `{:ok, appt}`. Accept → **capture**; decline → **cancel/void**; client cancel →
  refund only **outside** `:consultation_free_cancel_hours` (default 24h).
  `platform_fee_cents/1` via `:platform_fee_bps` (default **500** = 5%).
- **`AppointmentHoldExpiryWorker`** (hourly cron): auto-declines ~6-day-old holds before
  Stripe's ~7-day auth void.
- **Webhooks:** `checkout.session.completed` (mode `payment`), `.expired`,
  `payment_intent.canceled`/`.payment_failed`, `charge.refunded`, `charge.dispute.created`
  (currently **log-only**).
- **Test seam:** `:stripe_payment_client` → `Billing.StripePaymentClientStub`; tests in
  `professionals/appointment_payments_test.exs` + a webhook block in `stripe_handler_test.exs`.
- **Docs on the branch:** `docs/payments/nutritionist_payments_stripe_connect.md` and
  `docs/payments/go_live_and_pricing_steps.md` (the latter's "Part B" also bundles an
  unrelated nutritionist-price change to €30/€300).

### 1.3 Staleness / drift risks (why this isn't a clean cherry-pick)

- **59 commits of divergence.** The onboarding slice (§1.1) landed on master *separately*
  after the branch forked, so a straight merge will **collide on
  `professional_profiles`/`StripeHandler`/`Professionals`** — expect conflicts.
- **Fee unit drift.** The branch stores/enters the fee in **cents** (form labeled "in
  cents"); master evolved the field to a **euros** virtual (`consultation_fee_eur`). These
  must be reconciled — keep master's euros UX, keep the branch's cents storage.
- **Infra drift.** The branch's `go_live_and_pricing_steps.md` describes deploying via **AWS
  ECS + Secrets Manager**. Production is now **Fly.io + Supabase** (see
  `project_infra_fly_supabase`). Those go-live instructions are **obsolete** — redo them for
  Fly secrets.
- The auto-memory `project_nutritionist_payments` is the accurate record of this branch; it
  had (now-corrected) wording implying the flow was on mainline. It is not.

---

## 2. Architecture (as built on the branch — confirmed correct)

### 2.1 Express accounts
Stripe hosts onboarding **and performs KYC/KYB** (see §4.1). Already live on mainline.

### 2.2 Destination charge + `application_fee_amount`, **with `on_behalf_of`**

The branch sets `on_behalf_of = connected_account`, which makes the **nutritionist the
settlement merchant of record**. Consequences — note both:

- ✅ **VAT on the consultation is cleanly the nutritionist's** (they're the merchant of
  record for the service — see §4.4). Good for us.
- ✅ Stripe's processing fee is drawn from the nutritionist's 95%, not our 5%.
- ⚠️ **Disputes still hit the *platform* balance.** For destination charges, *with or
  without* `on_behalf_of`, Stripe debits dispute amounts + fees from the **platform**
  account. `on_behalf_of` does **not** move dispute liability to the nutritionist — see §4.2.
- ⚠️ Because the nutritionist is MoR and EEA-based, **SCA applies** to the client payment —
  the branch correctly uses Checkout (SCA-ready). See §4.3.

### 2.3 Manual capture = authorize on request, capture on accept
Matches our accept-first booking flow (`request_appointment` → `accept_appointment` /
`decline_appointment` / `cancel_appointment`). Auth holds expire ~7 days; the
`AppointmentHoldExpiryWorker` releases them at ~6 days. Correct.

### 2.4 Guard rails
Paid path only when `payable?/1` (onboarding done **and** fee > 0) **and** the
`:consultation_payments_enabled` flag is on; otherwise the existing free request flow. Good.

---

## 3. The plan (engineering) — resurrect, don't rebuild

### Step 1 — Rebase the branch onto master (the bulk of the work)

```bash
git checkout new_professional_nutritionist_features
git rebase master      # expect conflicts in professional_profiles, StripeHandler, Professionals
```

Resolve by **keeping master's evolved surfaces** and re-applying only the payment additions:

- **`professional_profiles`:** master already has the Connect columns + euros UX. **Drop the
  branch's duplicate onboarding/column work**; keep only what's genuinely new (if the branch
  added `consultation_currency`, port just that). Do **not** regress the euros field.
- **`StripeHandler`:** keep master's module; **append** `create_consultation_checkout/1`,
  `capture_payment_intent/1`, `cancel_payment_intent/1`, `refund_payment/2` and the new
  webhook branches.
- **`Professionals`:** re-apply `request_appointment/4` 3-tuple return, capture/cancel/refund
  wiring, `platform_fee_cents/1`, `payable?/1`, the flag helper.
- **Ledger migration** `20260919000002_create_professional_payments.exs`: renumber to a
  current timestamp so it sorts after master's migrations; confirm it doesn't collide.
- Port `AppointmentHoldExpiryWorker`, the Oban cron entry, the test seam + tests.

**Reconcile the fee unit:** master = euros in the form → cents in DB. Keep that; make the
payment math read `consultation_fee_cents` (already the storage). Delete the branch's
"enter in cents" label.

> Alternatively, if the rebase is too gnarly, cherry-pick the *payment-only* files
> (`appointment_payment.ex`, the migration, the `StripeHandler` charging block, the worker,
> the tests) onto a fresh branch off master and re-wire `Professionals`/`request_appointment`
> by hand. Often cleaner than resolving 59 commits of conflicts.

### Step 2 — Modernize the stale bits

- **Rewrite go-live ops for Fly.io + Supabase** (not AWS ECS/Secrets Manager). Stripe secrets
  are Fly secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` already set); any new price IDs
  go in via `fly secrets set` + redeploy.
- **Dispute handling:** the branch only *logs* `charge.dispute.created`. Upgrade to **alert
  us** (we carry the liability — §4.2) and record it on the ledger. Add
  `account.application.deauthorized` handling (clear account id, flip `charges_enabled`).
- Confirm the new webhook events are registered on the **current** Stripe endpoint.

### Step 3 — Verify end-to-end (test mode)

Follow the branch's A3 runbook (still valid): `stripe listen --forward-to
localhost:4000/webhooks/stripe`; nutritionist onboards + sets fee; client books with
`4242 4242 4242 4242`; confirm `professional_payments` → `authorized` + PI `requires_capture`
with 5% `application_fee_amount` + `transfer_data`/`on_behalf_of`; accept → `paid` + transfer;
decline → hold released; cancel-after-capture outside 24h → full refund incl. fee. Run
`appointment_payments_test.exs` + the webhook block.

### Step 4 — Flip the flag (go-live gate)

Only after §4's prerequisites are done: set `:consultation_payments_enabled` true in prod
config and deploy. This is the single switch that turns stored fees from "display-only, pay
out of band" into real card holds.

---

## 4. Our obligations (the compliance document)

Routing money between two parties makes M3Hungry a **payment facilitator / marketplace**,
with duties beyond code. **These were deferred when the branch was built and must be done
before go-live.** Each item is a **prerequisite** or an **ongoing obligation**.

### 4.1 KYC / KYB — who does what  *(mostly Stripe's job)*

- **Stripe collects and verifies KYC/KYB for Express connected accounts.** M3Hungry does
  **not** collect/store/verify nutritionists' ID, bank, or registration data — Stripe reaches
  out to the account directly. This is the core reason to use Express.
  ([Stripe: KYC for connected accounts](https://support.stripe.com/questions/know-your-customer-(kyc)-requirements-for-connected-accounts))
- **Our duty:** gate charging on `charges_enabled` (done), keep `account.updated` in sync
  (done), and keep the "resolve requirements / manage payouts" link reachable from
  `/nutritionist/profile`.
- **2026 EU verification changes (action required):** Stripe is tightening verification for
  **European** connected accounts — new accounts after **1 April 2026** meet updated
  requirements; platforms must refresh **existing** accounts' business info by
  **31 October 2026**. Express is Stripe-driven; we must not block/intercept Stripe's
  outreach and must confirm the account-link flow still works.
  ([Stripe: 2026 EU verification FAQs](https://support.stripe.com/questions/2026-updated-verification-requirements-for-europe-faqs-for-platforms?locale=en-GB))
- **KYC Refresh (ongoing):** periodic re-confirmation, Europe first; Stripe-driven for
  Express. ([Stripe: KYC Refresh](https://support.stripe.com/questions/kyc-refresh-upcoming-periodic-confirmation-requirements))

> **Bottom line:** we need KYC, and Express gives it to us — **Stripe is on the hook to
> perform it.** Never switch to a model where we collect identity data.

### 4.2 Dispute & negative-balance liability  *(this costs us money — plan for it)*

- With **destination charges, Stripe debits dispute amounts + fees from the *platform*
  (M3Hungry) balance** — **and `on_behalf_of` does not change this.** We are ultimately
  responsible for these disputes.
  ([Stripe: disputes on Connect](https://docs.stripe.com/connect/disputes),
  [Stripe: risk & liability](https://docs.stripe.com/connect/risk-management))
- A connected account can go **negative** from refunds/chargebacks; for Express the
  **platform is liable** for that negative balance. Stripe auto-recovers via
  `debit_negative_balances`, but **after 180 days an unrecovered negative balance is cleared
  from the platform reserve** — M3Hungry eats it.
  ([Stripe: Connect Reserves FAQ](https://support.stripe.com/questions/connect-reserves-faq))
- **Mitigations (some already in the branch, some to add):**
  1. Keep `debit_negative_balances` enabled on connected accounts.
  2. Capture only on acceptance (built), near the consultation where practical.
  3. Publish and enforce a clear **refund/cancellation policy** (§4.6).
  4. **Upgrade dispute handling from log-only to alert + ledger record** (Step 2) and respond
     with evidence (booking + consultation-note existence + comms).
  5. Be able to **disable a risky nutritionist's paid bookings** (flip their fee / un-gate)
     without deleting the account.

### 4.3 Strong Customer Authentication (SCA / 3-D Secure)  *(handled, keep it)*

- M3Hungry is an **EEA** platform with EEA nutritionists and clients, and `on_behalf_of`
  makes the nutritionist MoR → **SCA applies.** The branch authorizes via **Stripe Checkout**
  (PaymentIntents under the hood), which is **SCA-ready** and does 3-D Secure automatically.
  Do not introduce any raw-card or legacy-Charges path.
  ([Stripe: SCA for destination charges](https://support.stripe.com/questions/strong-customer-authentication-(sca)-for-destination-charges-created-by-non-european-economic-area-(eea)-platform-for-eea-based-connected-account-and-eea-based-customer),
  [Stripe: SCA readiness](https://docs.stripe.com/strong-customer-authentication))

### 4.4 VAT / tax  *(prerequisite decision — talk to an accountant)*

Two distinct supplies:

- **The consultation** (nutritionist → client): because `on_behalf_of` makes the
  **nutritionist the merchant of record**, the consultation's VAT is **cleanly the
  nutritionist's responsibility**, not ours. In Greece, health services by regulated
  professionals are often **VAT-exempt** — the nutritionist's call with their accountant.
- **Our 5% platform commission** (M3Hungry → nutritionist): a **B2B service** we supply.
  - Nutritionist in **Greece** → domestic B2B: we charge Greek VAT (**24%**) on the
    commission and issue an invoice.
  - Nutritionist in **another EU country** → **reverse charge**: invoice without VAT, noting
    reverse charge.
  ([Greece VAT guide](https://www.vatcalc.com/greece/greece-vat-guide/),
  [EU reverse charge](https://flexlogistics.eu/vat-reverse-charge-explained-eu-business/))
- **Actions:** (1) decide whether the stored 5% is VAT-inclusive or VAT-on-top — this changes
  `application_fee_amount` math, **get it right with an accountant before launch**;
  (2) **issue compliant invoices for the commission** (consider Stripe Tax/invoicing, but the
  duty is ours regardless); (3) record fee + any VAT on the ledger row. The branch's A4 note
  ("tax is the nutritionist's because of `on_behalf_of`") is right about the *consultation* but
  silent on *our commission* — close that gap.

> Most likely to need professional tax advice. Do not guess the fee's VAT treatment in code.

### 4.5 Accurate business representation & acceptable use  *(prerequisite — due diligence)*

- Represent the platform truthfully to Stripe: **nutrition consulting / health education +
  software marketplace.**
- **Watch the "telemedicine/telehealth" line** — Stripe restricts payment collection for some
  telemedicine and "unregulated health services." Credentialed-dietitian *counseling* is
  generally fine, but online health consultation is a gray area. **Before go-live, confirm
  with Stripe that our use is accepted, and don't frame it as medical telemedicine or make
  health-outcome guarantees.**
  ([Stripe: why some businesses aren't allowed](https://stripe.com/blog/why-some-businesses-arent-allowed),
  [Stripe restricted businesses](https://support.stripe.com/questions/stripe-atlas-restricted-business-categories))
- No unsubstantiated health claims in payment-adjacent copy (consistent with the YMYL posture
  already in CLAUDE.md).

### 4.6 Consumer-facing refund & cancellation policy  *(prerequisite — must publish)*

Even though the nutritionist is the service MoR, the client books and pays **inside
M3Hungry**, so we must publish and honor a clear policy: free-cancel window (the branch's
24h `:consultation_free_cancel_hours`), no-show handling, nutritionist-decline = released
hold (never charged), post-capture refund mechanics. Surface it at the paid-booking step and
in Terms. Reduces disputes (§4.2) and is an EU consumer-protection expectation.

### 4.7 Platform agreements  *(one-time)*

M3Hungry accepts the **Stripe Services Agreement + Connect platform terms**; each
nutritionist accepts the **Connected Account Agreement** inside Express onboarding (Stripe
presents it — don't bypass).

### 4.8 Data protection (GDPR)  *(ongoing)*

Creating charges/accounts sends personal data to Stripe (client email; nutritionist
identity/bank via onboarding). **List Stripe as a sub-processor/recipient** in the privacy
policy (`privacy_policy_live.ex`), ensure the **Stripe DPA** is in force, and keep sending the
minimum (email + amounts + metadata ids). Card data never touches our servers.

### 4.9 PCI scope  *(by design, low)*

Checkout means **card data never hits our servers** → lightest PCI tier (**SAQ A**). Never add
a flow that posts raw card numbers to our backend.

---

## 5. Config & operations

- **Reuse** `STRIPE_SECRET_KEY` / `STRIPE_WEBHOOK_SECRET` (same platform account as
  subscriptions). Config keys: `:consultation_payments_enabled` (go-live switch),
  `:platform_fee_bps` (500), `:consultation_free_cancel_hours` (24).
- **Enable Connect** + set **platform profile, branding, support details** in the Stripe
  dashboard (shown in Express onboarding + on client receipts). *(Prerequisite.)*
- **Register webhook events** (§1.2 + the two Step-2 additions) on `/webhooks/stripe`.
- **Confirm `debit_negative_balances`** on created accounts (§4.2).
- **Deploy via Fly.io secrets**, *not* AWS — the branch's go-live doc is obsolete here.
- Everything **test-mode first** (Connect has full test mode incl. simulated payouts/disputes).

---

## 6. Open decisions (need a human call)

1. **VAT on our commission** — inclusive vs on-top; invoicing mechanism (§4.4). *Accountant.*
2. **Refund/cancellation policy** specifics (§4.6). *Business.*
3. **Stripe acceptable-use confirmation** for paid nutrition consultations (§4.5). *Business.*
4. **Fee level** — keep 5% (`:platform_fee_bps` 500)? *Business.*
5. **Rebase vs. cherry-pick** the branch (§3 Step 1). *Eng.*
6. Whether to also take the branch's bundled **€30/€300 nutritionist price change** now or
   separate it. *Business.*

---

## 7. Effort & sequencing

| Phase | Work | Effort | Prereq |
|---|---|---|---|
| **A. Compliance groundwork** | §4.4 VAT decision, §4.5 Stripe use confirmation, §4.6 policy, §4.8 privacy update, §5 dashboard/branding | ~1–2 days elapsed (mostly non-eng) | **must precede go-live** |
| **B. Rebase/cherry-pick branch** | Step 1 — resolve 59-commit drift, reconcile fee unit, renumber migration | ~1–1.5 days | — |
| **C. Modernize** | Step 2 — Fly go-live rewrite, dispute alert+ledger, deauthorized webhook | ~0.5 day | B |
| **D. Verify** | Step 3 — test-mode end-to-end + existing test suite green | ~0.5 day | B, C |
| **E. Go-live** | Step 4 — register webhooks, enable Connect, flip flag, prod smoke | ~0.5 day | A, D |

**~3 engineering days** (less than a greenfield build — the logic exists), but **do not flip
`:consultation_payments_enabled` until Phase A is done.** Code can be rebased/tested in
parallel with the compliance work; they converge at go-live (Phase E).

---

## 8. Cross-references

- Onboarding slice + original assessment: `nutritionist_payments_stripe_connect.md`
- The built-but-unmerged flow: branch `new_professional_nutritionist_features` (`5d91fde5`);
  its own `docs/payments/go_live_and_pricing_steps.md` (go-live runbook — AWS parts obsolete)
- Booking lifecycle: `docs/features/professionals/appointments_booking.md`
- Existing single-party billing: `docs/features/subscriptions_billing.md`,
  `Mehungry.Billing.StripeHandler`
- Infra (why AWS refs are stale): memory `project_infra_fly_supabase`
