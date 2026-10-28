# Growth Plan — Nutritionist-led (Oct 26 → Nov 23, 2026)

**Baseline source:** [docs/app_status.md](../implementation/app_status.md) (snapshot 2026-10-17)
**Positioning source:** the nutritionist one-pager + [product_foundation.md](../features/product_foundation.md) —
the product leads with **professional nutritionists**; the consumer food/recipe layer is the second ring.
**Cadence:** review every Friday against the weekly sprint; append the Week-4 retro here and a
new row to [app_status.md §6](../implementation/app_status.md#6-snapshot-log).

> **Reset (2026-10-26):** this plan was rewritten when the product repositioned to lead with
> professional nutritionists. The previous version optimised for consumer signups in Crete; that
> work survives only as the **proof/surfacing ring** (below), not the headline.

---

## Thesis

The moat is **research + surfacing wired into the clinical workflow** — graded, provenance-backed
PubMed digests per condition, and suggested notes that resurface on the exact client who has that
condition. Profiles, booking, client files, and billing are **parity**: they earn the seat at the
table next to Healthie / Practice Better / Nutrium, but they don't win. Everything we do this month
is in service of getting a nutritionist to the moment where they *feel* the research→client loop.

So growth is **not** raw consumer signups. It is:

1. **Make the two must-be-true things true** — the differentiators are real in the architecture; the
   risk is **coverage and quality, not features**. Research only impresses when the conditions a
   nutritionist actually cares about have digested papers behind them, and the AI meal planning has
   to be genuinely good, not just present.
2. **Land and activate nutritionists** — founder-led, un-scalable, where Greek/Crete dietitians
   physically are. One activated nutritionist is worth more than fifty passive consumer signups.
3. **Let the motion be B2B2C** — an activated nutritionist brings their clients, who become users.
   The consumer layer (`/foods`, SEO, share cards) is the credibility/surfacing proof engine
   underneath, not the acquisition target.

**No paid ads this month.** Don't scale acquisition into a product whose moat isn't yet proven on
the conditions that matter.

---

## Month targets (Oct 26 → Nov 23)

Targets are ordered: **1 & 2 are the moat readiness gates and matter most** — a nutritionist who
hits the research→client loop on an empty condition churns. 3–5 are the nutritionist motion; 6–7 are
the proof/surfacing ring.

| # | Metric | Baseline | Target | Floor | Measured by |
|---|---|---:|---:|---:|---|
| 1 | **Condition coverage** — curated "top-20 conditions nutritionists care about" with ≥5 digested papers each | ~0 | ≥15/20 | 10/20 | `research_ingestion_runs` + studies/condition |
| 2 | **AI meal-plan quality** — plans passing the review rubric (realistic, condition-aware, nutritionally sound) | unmeasured | ≥80% pass | 60% pass | manual rubric, n≥20 drafts |
| 3 | **Nutritionists onboarded** — public profile live + indexed in the directory | ~0 | 5 | 3 | `Professionals` profiles |
| 4 | **Nutritionists activated** — completed the loop: saved a suggested note **and** saw it resurface on a real client with that condition | 0 | ≥3 | 2 | `research_notes` + `professional_client_conditions` |
| 5 | **Parity proof** — ≥1 nutritionist completes a real booking (accept → `.ics`) and finishes Stripe Connect onboarding | 0 | 1 | 0 (1 in progress) | appointments + Connect status |
| 6 | **B2B2C clients** — users brought in via a nutritionist's client roster | 0 | ≥10 | 5 | `ProfessionalClient` → `User` |
| 7 | **Discoverability seeded** — directory + per-profile local schema indexed; first "nutritionist in <city>" impressions >0 | n/a | indexed + impressions >0 | indexed | Search Console |

> If target 1 or 2 is red at any Friday check, **pause nutritionist outreach** and fix the moat
> first — demoing the loop over an empty or wrong-feeling condition burns the relationship.

---

## Weekly sprints

### Week 1 (Oct 26–Nov 1) — Make the moat true + arm the directory
*The differentiators are architectural; this week closes the coverage/quality gap before any demo.*

**Targets:** condition coverage ≥10/20, AI meal-plan rubric run (n≥20), directory SEO verified.

- **Condition coverage sweep:** pick the top-20 conditions real Greek dietitians ask about; run
  research ingestion (`/professional/health` → "Research ingestion") for each; confirm each has ≥5
  graded papers with claim highlighting in the reader and at least one promotable **suggested note**.
- **AI meal-plan quality rubric:** draft 20+ plans across those conditions; score each (realistic
  dishes, condition-aware, macro/nutrient sanity, "still 100% you" edit-ability); log failures as
  fixes. This is a gate, not a vanity pass.
- **Directory SEO:** verify the public directory + each `/nutritionists/:slug` emits local-business
  schema; submit the directory + `/el` sitemap to Search Console; request indexing; check
  hreflang/canonical.
- **End-to-end loop smoke test:** as a test nutritionist, save a suggested note on condition X, link
  a test client to condition X, confirm the note resurfaces on that client. Fix any seam.

### Week 2 (Nov 2–8) — Land nutritionists where they are
*Founder-led outreach to Greek/Crete dietitians; lead with the loop, not the calendar.*

**Targets:** 3–5 live profiles onboarded, 1 booking/payout flow started, 3 real demos given.

- **Direct outreach:** DM/email 10–15 Greek dietitians (University of Crete / ΕΛΜΕΠΑ networks,
  professional associations, local practices). Pitch = free Pro + "the research layer your software
  doesn't have, wired to your client files."
- **Demo the moat, not the menu:** every demo ends on the research→client loop and a condition they
  named. Use their real condition from Week 1's coverage set.
- **Onboard profiles:** get 3–5 discoverable profiles live (photo, bio, city, availability) so the
  directory has real inventory to index.
- **Parity proof:** walk one nutritionist through a real booking + Stripe Connect onboarding so the
  "earns the seat" claims are demonstrably true.

### Week 3 (Nov 9–15) — Activate the loop + open B2B2C
*Turn a live profile into an activated practitioner, then into their clients.*

**Targets:** ≥2 nutritionists activated (hit #4), ≥5 B2B2C clients, 2–3 evidence-referenced articles.

- **Activation push:** sit with each onboarded nutritionist until they (a) save a suggested note and
  (b) link a real client to a condition and see the note resurface. That moment *is* activation.
- **B2B2C:** help one nutritionist import/add their client roster (CSV import or by-hand records);
  those clients become platform users. Credibility: their records hold real PII and intake
  (BMI/BMR/TDEE auto-calc), visit timeline.
- **Content as reach:** have (or ghost-draft with) a nutritionist publish 2–3 evidence-referenced
  Articles targeting long-tail Greek searches ("εβδομαδιαίο πρόγραμμα διατροφής",
  "μεσογειακή διατροφή"), each with a numbered bibliography citing first-class entities.
- **Kill/scale:** double down on whatever outreach channel produced an *activated* nutritionist.

### Week 4 (Nov 16–23) — Retain, prove the loop, measure
*Make the first activated nutritionists the loyal core; decide next month from evidence.*

**Targets:** hold #4 ≥3, #6 ≥10, publish snapshot + retro.

- **Retention 1:1s:** ask each activated nutritionist what almost made them stop, and what condition
  coverage they still want — feeds next month's ingestion list.
- **Surfacing proof ring:** post the week's best AI recipe social-graphics + a nutritionist Article
  to IG/Pinterest/FB; confirm the consumer `/foods` SEO is accruing GSC impressions underneath.
- **Measure:** run the queries for targets 1–7, append the
  [app_status.md §6](../implementation/app_status.md#6-snapshot-log) snapshot row, write a 5-line
  retro (cost per *activated nutritionist* per channel; which conditions drove activation;
  kill/2× decisions).

---

## Week-over-week watch list

1. **Condition coverage** — are the conditions nutritionists actually name backed by digested papers?
2. **AI meal-plan quality** — rubric pass rate trending up, or still producing plans a clinician would reject?
3. **Nutritionists activated** — did anyone complete the research→client loop (not just sign up)?
4. **B2B2C clients** — are activated nutritionists pulling their roster in?
5. **Discoverability** — directory/profile indexing + first "nutritionist in <city>" impressions.

---

## Engineering checklist

Tracked in code. `[code]` = app change, `[ops]` = console/DNS (human-applied).

### A. Moat readiness (the two must-be-true things)
- **A1 [ops/content]** Define the curated top-20 conditions list; run research ingestion per
  condition; verify ≥5 graded papers + claim highlighting + a promotable suggested note each.
- **A2 [code]** Verify the research→client loop end to end: save suggested note → link client to
  condition → note resurfaces on that client's view (`research_notes` × `professional_client_conditions`).
- **A3 [process]** AI meal-plan quality rubric: score ≥20 drafts across the target conditions; file
  the failure modes as fixes; set the pass bar at ≥80%.

### B. Discoverability (built-in, not the practitioner's problem)
- **B1 [code]** Confirm the public directory + each `/nutritionists/:slug` emit local-business schema
  and are in the sitemap; submit to Search Console and request indexing.
- **B2 [code]** Open Graph / Twitter-card meta on profiles + Articles for rich FB/Pinterest unfurls.

### C. Parity credibility (earns the seat)
- **C1 [code/ops]** One real booking flow (availability → request → accept → branded email + `.ics`)
  plus Stripe Connect onboarding completed by a real nutritionist.
- **C2 [code]** CSV import + by-hand `ClientRecordEditor` path verified so a nutritionist can bring a
  real roster (BMI/BMR/TDEE auto-calc, visit timeline).

### D. Signup funnel (nutritionists + their clients still have to confirm)
- **D1 [ops]** Audit SPF/DKIM/DMARC on `m3hungry.com` for **Mailgun EU**; confirm the domain is
  verified (not sandbox); score a test send on mail-tester.com (≥9) and confirm Gmail Primary
  placement. Sender: `noreply@m3hungry.com`.
- **D2 [code]** Registration surfaces a resend path when a Mailgun deliver fails, and logs the reason.
- **D3 [code]** Confirmation email expiry copy corrected to **7 days** (matches `@confirm_validity_in_days`).
- **D4 [code]** Confirmation email **localized to Greek** (`el`), switched on user locale.
- **D5 [code]** "Resend confirmation" link surfaced from the registration success flash and the login page.

### E. Surfacing / proof ring (the consumer second ring)
- **E1 [code]** Weekly-program share + "Made with m3hungry.com" referral footer + OG meta on the
  public blueprint share page (`/blueprints/:slug`).
- **E2 [code, deferred]** When the image/PDF export lands, bake the brand lockup in by reusing
  `MehungryWeb.InsightGraphic.wordmark/0` — not a new convention.
