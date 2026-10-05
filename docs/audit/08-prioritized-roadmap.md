# 08 — Prioritized Roadmap

*A single ranked backlog synthesising all sections. Prioritization weighs **severity/impact × confidence ÷ effort**, with the rule that **legal/user-harm risks outrank easy marketing wins.** Effort: S (≤1 wk), M (1–4 wks), L (1–3 mo). Each item notes if it's **blocked** by missing info or expert review.*

## Tier 0 — Critical legal / safety (do first; mostly low effort, high exposure)

| # | Action | Why (evidence) | Impact | Effort | Success measure | Blocked by |
|---|--------|----------------|--------|--------|-----------------|------------|
| 0.1 | Gate GA gtag.js behind consent; make "Reject" = "Accept" | GA loads before consent (`head.html.heex:174-186`) — R6 | Removes a classic ePrivacy enforcement target | S | No third-party analytics request fires before `cookie_consent==:accepted` | — |
| 0.2 | Correct the false "data not shared with any other party" line | `privacy_policy_live.ex:14` is affirmatively misleading — R7 | Removes a UCPD/Art.5 misstatement | S | Statement replaced with accurate processor disclosure | — |
| 0.3 | Make account deletion complete + safe | Omits health-PII tables; destructive GET; `professional_clients.user_id` only nilified — R4 | Real Art. 17 erasure; removes CSRF/accidental-delete risk | M | Deletion covers/anonymises all PII + health tables; POST + re-auth + accurate copy | Decide retention vs erasure for pro records (legal) |
| 0.4 | Put a basic staff AI-literacy measure in place | AI Act Art. 4 in force since Feb 2025 — R8 | Closes an overdue duty | S | Documented literacy measure exists | — |
| 0.5 | **Health-claims audit** of condition→food statements vs EU Register | Likely unauthorised claims — R1 (**Critical**) | Avoids food-authority enforcement/takedown | L | Each surfaced statement mapped; unauthorised ones removed/rephrased | **EU food-law counsel** |
| 0.6 | **MDSW qualification opinion** + documented non-medical intended purpose | Possible unregistered medical device — R2 | Avoids device-regime exposure | M→L | Written qualification opinion; intended-purpose design doc | **MDR counsel** |
| 0.7 | **DPIA** + controller/processor roles + Art. 28 DPAs + explicit health-data consent | Special-category data, no Art. 9 basis — R3 (**Critical**) | Makes health processing lawful | L | DPIA done; DPAs signed; explicit consent captured at intake/opt-in | **Privacy counsel** |

## Tier 1 — High-impact compliance + funnel (short term, 2–6 weeks)

| # | Action | Why | Impact | Effort | Success measure | Blocked by |
|---|--------|-----|--------|--------|-----------------|------------|
| 1.1 | Publish full Art.13/14 privacy notice + ToS + Impressum + DSA contact point | R7, R11 | Baseline legal + trust | M | Pages live; processors/transfers/retention/rights disclosed | Operating-entity identity |
| 1.2 | Add CRD pre-contractual info + 14-day withdrawal notice/form; confirm Stripe Tax VAT | R9 | Lawful paid subscriptions | M | Withdrawal flow + VAT-inclusive pricing + invoices | Confirm Stripe Tax config |
| 1.3 | End-user "AI-generated" labelling + AI-interaction notices | R8 (Art. 50 ~Aug 2026) | AI Act transparency + honesty | S→M | Published AI recipes/images labelled; agents disclose AI | — |
| 1.4 | DSA notice-and-action + reporting UI for UGC | R11 | Hosting-tier duty (size-independent) | M | Report flow + reasoned decision/appeal path | — |
| 1.5 | Build data export (Art.15/20) + SAR/erasure runbook | R5 | DSR readiness within 1 month | M | Self-service JSON/CSV export covering profile/recipes/plans/history | — |
| 1.6 | **Give free tier a taste of AI** (sample gens or 14-day no-CC Pro trial) | 0-quota paywalls the headline feature — [market-fit](04-market-fit.md) | Unblocks activation/conversion | S | New users experience AI before the paywall; trial→paid measured | — |
| 1.7 | **Client-logging PWA** stopgap | Web-only kills daily logging — [market-fit](04-market-fit.md) | Preserves the "see what clients eat" differentiator | M | Installable PWA; clients log on phone | — |
| 1.8 | Guided onboarding (sample client + one-click sample plan); CSV import up front | Long activation path — [GTM](07-go-to-market.md) | Lifts dietitian activation | M | Signup→first plan assigned ≤7 days rate tracked & rising | — |
| 1.9 | Restore visible keyboard focus styles | `outline:none` globally (`head.html.heex:157-164`) — R12/WCAG 2.4.7 | Accessibility + good practice | S | Focus visible on all interactive elements | — |

## Tier 2 — Market validation (run in parallel; cheap, decision-driving)

| # | Action | Why | Effort | Success measure | Blocked by |
|---|--------|-----|--------|-----------------|------------|
| 2.1 | Dietitian concierge liquidity test (E3) | Validates the whole B2B thesis | M | ≥30% of 15–25 pros get ≥1 consult; ≥50% would keep paying | Booking-payment flow (3.1) for true paid test |
| 2.2 | Wedge-message landing test (E1) | Validates positioning before spend | S | Exactness message ≥2× breadth CTR; ≥4% register | — |
| 2.3 | Mobile-gap + web logging-retention smoke test (E2) | Sizes the native-app decision | S | Quantifies mobile demand + D7 logging retention | — |
| 2.4 | AI willingness-to-pay fake-door (E4) | Re-weights quotas/messaging | S | One variant ≥2× the other | — |
| 2.5 | Condition-science trust + legal screen (E5) | Keep/cut the science layer | S | >25% engage AND no regulatory red flag | Depends on 0.5 |

## Tier 3 — Positioning & messaging (fast, high-leverage)

| # | Action | Why | Effort |
|---|--------|-----|--------|
| 3.0 | Ship the B2B landing variant + positioning statement ([§6](06-positioning-strategy.md)) | Re-focuses from Cronometer's losing fight to the defensible dietitian wedge | M |
| 3.0b | Add founder identity + trust marks + honest disclaimers; drop unsupported "nutrient interactions per recipe" claim | Credibility + honesty (R7, marketing-vs-reality) | S |

## Tier 4 — Acquisition & distribution (after funnel + legal fixes)

| # | Action | Why | Effort |
|---|--------|-----|--------|
| 4.1 | Founder-led outreach to 100 Greek dietitians → 10 founding partners | Highest-fit channel ([GTM C1](07-go-to-market.md)) | M |
| 4.2 | 10 directory/city pages + 10 Greek condition articles (health-claims-screened) | Compounding SEO ([GTM C2](07-go-to-market.md)) | M |
| 4.3 | Referral loops (dietitian referral + "invite your dietitian") | Near-zero-CAC scale ([GTM C3](07-go-to-market.md)) | M |
| 4.4 | Email lifecycle (consent-compliant) | Amplifies all channels | S |

## Tier 5 — Build the marketplace revenue (medium term; currently fiction)

| # | Action | Why | Effort | Blocked by |
|---|--------|-----|--------|------------|
| 5.1 | **Finish + merge the paid-booking flow** (branch `new_professional_nutritionist_features`: `appointment_payment.ex` + application fee) | Built but unmerged; absent from master/current (`stripe_handler.ex:74`) — [feature inventory](02-product-feature-inventory.md) | M→L (rebase/review, not build from scratch) | VAT/intermediary structuring (R13) |
| 5.2 | Marketplace trader traceability if DSA Art. 30 in scope | R11 | M | Confirm enterprise size |
| 5.3 | Fix `CLAUDE.md` + memory to say paid bookings live on an **unmerged branch**, not the mainline | Stale docs mislead planning | S | Docs match code reality |

## Tier 6 — Longer-term / conditional

- **Native mobile app** — only after 2.3/1.7 prove logging retention is the binding constraint. L.
- **Deepen nutrient DB credibility** (e.g. Open Food Facts for EU packaged goods) — if staying in consumer nutrition at all. M.
- **Clinical depth for Pro** (invoicing/charting) — only if B2B traction warrants competing with Nutrium/Healthie feature-for-feature. L.
- **Consolidate the two meal-plan models** (`Plans.*` vs `History.UserMeal`) — tech-debt cleanup. M.

## What NOT to build (absent new evidence)

- A bigger social network — it's a feature, not a business here.
- More of the PubTator/compound science layer as a *consumer* feature — high cost, unproven pull, and the legal exposure (R1/R2) must be resolved first.
- Paid consumer acquisition — until the funnel leaks (1.6/1.7/1.8) are closed.

## Suggested sequencing (one line)

**Tier 0 legal + Tier 1 funnel fixes → Tier 2/3 validation + re-positioning → Tier 4 outreach/SEO → Tier 5 payment rails → Tier 6 conditional bets.** Do not let the easy marketing wins (Tier 3/4) jump ahead of the Tier 0 legal items.
