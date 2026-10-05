# 09 — Open Questions & Assumptions

*These materially affect the conclusions. Each notes which finding it changes and the cheapest way to resolve it.*

## Questions that change the legal determination

| # | Question | Why it matters | Affects | How to resolve |
|---|----------|----------------|---------|----------------|
| Q1 | **Which legal entity operates Mehungry, and in which Member State?** | Drives lead supervisory authority, Impressum content, DSA legal-rep need, applicable national transpositions | R7, R11, all GDPR | Founder states it |
| Q2 | **Enterprise size (headcount + turnover)?** | Switches DSA Art. 29 and EAA micro-enterprise exemptions on/off | R11, R12 | Founder states it |
| Q3 | **Is the platform controller, joint controller, or processor of nutritionist client records?** | Determines who owes Art. 9/13/28 for the health PII | R3, R4 | Legal analysis of the pro↔client relationship |
| Q4 | **Is the condition→food feature "commercial communication"/food information, or editorial scientific information?** | Determines whether Reg. 1924/2006 bites at all | R1 (Critical) | EU food-law counsel |
| Q5 | **What is the *marketed* intended purpose of the health/meal-plan/nutritionist AI — wellness or disease management/prevention?** | Determines MDR qualification | R2 | MDR counsel + a deliberate intended-purpose decision |
| Q6 | **Is the paid subscription a digital "service" or "content"?** (Personalisation suggests *service* post-CJEU C-234/25) | Governs the 14-day withdrawal mechanics | R9 | Consumer-law counsel |
| Q7 | **Does Stripe Tax actually handle EU VAT + issue compliant invoices?** | Determines the VAT/invoicing gap severity | R9, R13 | Check the Stripe dashboard config (not visible in code) |
| Q8 | **DPF-certification / SCC status of each US sub-processor; does any special-category data reach the AI providers?** | Determines Ch. V transfer exposure | R14 | Vendor DPA review + a data-flow trace |

## Questions that change the product/market conclusions

| # | Question | Why it matters | Affects | How to resolve |
|---|----------|----------------|---------|----------------|
| Q9 | **How fully populated are the nutrition / compound / condition tables in production?** | Not verifiable from code; "168 nutrients" and condition→food richness depend on it | marketing-vs-reality, [market-fit](04-market-fit.md) | Query prod DB counts |
| Q10 | **Is there any real usage today — registrations, active users, retention, paid conversions, active nutritionists, completed bookings?** | No public evidence found; PMF cannot be assessed without it | [market-fit](04-market-fit.md) | Pull internal analytics / GA4 / DB |
| Q11 | **Will the unmerged paid-booking branch be finished and merged?** | *Resolved during this audit:* the flow (`appointment_payment.ex` + `application_fee`) exists on branch `new_professional_nutritionist_features` (commit `5d91fde5`) but is **not** on master or the current branch. So it's a *merge/finish* task, not a build-from-scratch. Open part: is that branch current and intended to ship? | [feature inventory](02-product-feature-inventory.md), roadmap 5.1 | Review/rebase `new_professional_nutritionist_features` |
| Q12 | **Is encryption-at-rest + access control applied to `client_intakes` health PII beyond ownership scoping?** | Security of special-category data | R3 | Infra/DB review |
| Q13 | **Does the operator intend a consumer or a professional product as the primary business?** | Determines whether Direction C (recommended) is acceptable | [positioning](06-positioning-strategy.md) | Founder decision |
| Q14 | **Is Greece the intended beachhead, or a broader EU/global launch?** | Shapes the whole GTM (localization moat, outreach universe) | [GTM](07-go-to-market.md) | Founder decision |

## Assumptions made in this audit (flag if wrong)

1. **Operator is EU-established** (€ pricing, el/en locales, AWS eu-central-1). If not, GDPR/DSA still likely apply via the targeting criterion, but the specifics (lead authority, EU legal rep) shift — see Q1.
2. **Bootstrapped / effectively solo founder** (single admin, owner email bypasses quota, honest stat-free landing). Drives the "focus + low-budget channels" strategy. If funded/larger, consumer Direction A/B become more viable and more legal duties (DSA/EAA) attach.
3. **Pre-traction** — no public user/revenue data was found; the audit treats PMF as unproven (Q10).
4. **The code on branch `f/exporting_weekly_proram` reflects what is/will be deployed.** Features on other branches or in the non-deployed `mehungry_local_ai` app were not assessed as production surface.
5. **External market/legal figures are as cited (accessed 2026-10-05)** and may move; treat competitor prices and legal deadlines as point-in-time.
6. **The nutritionist marketplace does not collect payment on master/current** — verified by grep; the payment code lives on the unmerged `new_professional_nutritionist_features` branch (Q11).

## The five answers that most change the plan

If the founder answers only five, make them: **Q2** (size → which laws apply), **Q4+Q5** (health-claims/MDR → whether the health features can ship at all), **Q10** (real traction → is this pre- or post-PMF), **Q11** (merge the paid-booking branch?), and **Q13** (consumer vs professional intent → whether the recommended pivot is acceptable).
