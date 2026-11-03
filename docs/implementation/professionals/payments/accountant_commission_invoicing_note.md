# Note for the accountant — invoicing the M3Hungry platform commission

**From:** Nikolaos Galerakis (M3Hungry, sole trader, Greece)
**Date:** 2026-11-03
**Status:** current platform income from this = **€0** (feature not yet live). We want the
invoicing mechanism agreed **before the first consultation is paid**, not after.

## What M3Hungry does

M3Hungry is an online platform where independent **nutritionists** offer paid consultations to
clients. When a client books:

- The client's card is charged through **Stripe** (Stripe Connect, destination charge).
- The **nutritionist is the merchant of record** (we use Stripe `on_behalf_of`), so the money
  for the consultation is theirs.
- M3Hungry automatically keeps a **flat 5% platform commission** on each booking (Stripe deducts
  it as an `application_fee` and settles it to our balance). Stripe does **not** issue any invoice
  for this on our behalf.

So there are **two separate transactions**:

| # | Who → who | For what | Whose VAT duty |
|---|---|---|---|
| 1 | Client → nutritionist | the consultation | the **nutritionist's** (they're merchant of record) |
| 2 | Nutritionist → M3Hungry | the **5% commission** | **ours** — this note is about this one |

Transaction 1 is not our concern. **Transaction 2 is the B2B service we supply and must invoice.**

## What we've already decided (for context)

- The **5% commission is VAT-inclusive** — the 5% is the gross; VAT is contained within it, not
  added on top. Economics are identical for the nutritionist regardless of country.
- Our system records, for every booking, the gross fee **and** the VAT portion
  (`fee_vat_cents`, computed at 24%). So the data for invoicing already exists per transaction.
- Greek nutritionist: VAT ≈ fee − fee/1.24, net to us ≈ **4.03%** of the booking.
- Other-EU nutritionist: expected to be **reverse charge** (invoice without VAT, whole 5% ours).

## What we need you to confirm / decide

1. **The invoicing mechanism** — the main open question. How should we issue compliant invoices
   for the 5% commission?
   - via our Greek **myDATA / e-invoicing** obligation (and is it mandatory for us)?
   - via accounting software, or via **Stripe Tax / Stripe Invoicing**?
2. **Cadence** — one invoice **per booking**, or a **monthly aggregate** invoice per nutritionist?
3. **VAT-inclusive bookkeeping** — confirm how to book it: we never raise a separate charge (the
   5% just arrives in our Stripe balance), yet we owe Greek VAT (24%) on the Greek-nutritionist
   portion. How is that recorded/remitted?
4. **EU cross-border → reverse charge** — for a nutritionist in another EU country: confirm we
   invoice **without VAT marked "reverse charge"**, what we must capture (their **VAT ID**,
   VIES-validated) and whether a **recapitulative statement** is owed.
5. **Our VAT registration status** — confirm we're registered / above threshold to be charging
   VAT on B2B commission.
6. **Invoice content** — what each commission invoice must legally show under Greek rules.

## Timing

We can switch the paid feature on technically at any time. We will **not take real bookings until
the invoicing mechanism above is agreed** — but since income is currently €0, there is no overdue
obligation today. Target: settle this with you, then go live.

> Source of truth for the money mechanics:
> `docs/implementation/professionals/payments/nutritionist_payments_build_plan.md` §4.4.
