# Nutritionist Analytics — Earnings & pipeline

The nutritionist-gated analytics page at **`/nutritionist/analytics`**
(`MehungryWeb.NutritionistLive.AnalyticsLive`). It answers the three questions a
solo practice actually acts on: *am I getting paid, is my calendar full, and
where is money leaking?* — read straight from the Stripe Connect payments ledger
(`professional_payments`), never from Stripe directly.

Reachable from the nutritionist sidebar ("Analytics", `hero-chart-bar`). Gated by
`NutritionistAuthLive` like the rest of `/nutritionist/**` (pro subscription
required; a non-nutritionist is redirected to `/home`).

## What it shows

A time-range control (**This week · This month** (default) **· All time**) scopes
everything below it.

- **Hero KPI tiles**
  - **Net earned** — captured earnings for the range, net of our 5% platform fee
    and any refunds. The honest take-home, labelled "after 5% platform fee".
  - **In flight** — gross value of authorized-but-uncaptured holds (bookings
    awaiting the nutritionist's accept). Prompts a same-day action.
  - **Pending requests** — count of `requested` appointments, linking to the
    calendar to accept/decline.
- **Revenue over time** — net € per period (per-day within a week/month, per-month
  for all-time), plus a small appointments-per-week bar and the active-client count.
- **Where it came from** — a breakdown of net revenue by a selectable dimension:
  - **By service** — which `ProfessionalService` (intro / session / package) earned
    what. Top 6, remainder folded into "Other".
  - **New vs returning** — first-time vs repeat clients, classified by each client's
    lifetime-first captured payment.
  - **By outcome** — captured / no-show-retained / refunded / released.
- **Outcome strip** (shown only when there's refund/release leakage) — the four
  outcome buckets as € figures: Captured · No-show retained · Refunded ·
  Released (declined/expired holds, €0 earned).

**Empty state is first-class.** With no captured or in-flight payments yet (the
common starting point, and the state while `:consultation_payments_enabled` is
off), the revenue panels show a "No revenue recorded yet" prompt instead of empty
charts; the client/appointment context stays live.

## Deliberately NOT included: demographic revenue cuts

The page does **not** break revenue down by client **age, gender, or condition**,
and this is an intentional product decision, not an omission:

- At the single-digit client counts a solo practice has, "revenue by gender/
  condition" effectively discloses **per-client earnings** (small-N
  re-identification).
- Condition is **GDPR Article 9 special-category health data**; building a revenue
  analytics product keyed on it is a new processing purpose with near-zero
  decision value for the nutritionist.
- It invites optimising a *health* practice toward a protected characteristic.

The breakdowns we ship instead (service / new-vs-returning / outcome) are the
decision-relevant, privacy-safe cuts. Do not add demographic revenue segmentation
without a specific, justified reason and the matching DPA/safeguards (minimum
bucket-size suppression at the very least).

## Where the numbers come from

All aggregation is **SQL `GROUP BY`/`sum` in `Mehungry.Professionals`** — no payment
rows are loaded into the LiveView. Net is the single shared formula
`amount_cents − platform_fee_cents − refunded_amount_cents` over rows the
nutritionist keeps money on (`paid` + `partially_refunded`), identical to
`AppointmentPayment.net_cents/1`, so the dashboard can never drift from the ledger.

| Figure | Function |
|---|---|
| Net earned (range) | `net_earnings_cents/2` (all-time alias: `professional_net_earnings_cents/1`) |
| In flight | `in_flight_cents/1` |
| Pending requests | `count_pending_requests/1` |
| Revenue over time | `revenue_per_period/3` (`:day`/`:week`/`:month`) |
| Appointments/week | `appointments_per_week/2` |
| By service | `revenue_by_service/2` |
| By outcome | `revenue_by_outcome/2` |
| New vs returning | `revenue_new_vs_returning/2` |

A `date_range` is `:all` or a `{start_ndt, end_ndt}` `NaiveDateTime` tuple, applied
on `captured_at` (coalescing to `inserted_at`).

Charts reuse the existing Vega-Lite pattern (`Hooks.VegaLite`, `width: :container`
so the three charts stay responsive), with basil (`#45C4AE`) marks to match the
nutritionist section.

## Caveats

- **Single currency.** Sums assume one currency (default `eur`); mixed-currency
  practices would need per-currency grouping before summing raw cents.
- **UTC period boundaries.** "This week"/"this month" are computed in UTC. Times
  are stored UTC end-to-end today; resolving boundaries in the nutritionist's
  profile `timezone` is a documented follow-up.
- **Needs payments live.** The revenue half has data only when
  `:consultation_payments_enabled` is on (see
  `docs/implementation/professionals/payments/nutritionist_payments_stripe_connect.md`);
  otherwise it renders the empty state.
