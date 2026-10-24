# Legal & Privacy Review — M3Hungry (2026-10-13)

> **Not legal advice.** This is an engineering-side review to get the user-facing
> legal documents into a defensible shape and to flag what still needs a qualified
> lawyer. It builds on the deeper analysis in
> [`docs/audit/03-eu-compliance-risk-register.md`](../audit/03-eu-compliance-risk-register.md)
> (R1–R14) and does not replace it.

## 1. What M3Hungry does with personal data (the surface being reviewed)

| Category | Where it comes from | Sensitivity |
|---|---|---|
| Account (email, hashed password, OAuth profile) | Registration, Facebook/Google/Instagram sign-in | Normal |
| Profile & preferences (diet, survey, calorie target, **health-condition badges**) | `Accounts.UserProfile` opt-in | **Special category (health)** |
| User content (recipes, comments, votes, posts, meal plans, baskets, media) | User-generated | Normal |
| **Nutritionist client records** (height/weight/BMI/BMR/TDEE, goals, free-text medical notes) | `Professionals.ClientIntake` / `ConsultationNote` / CSV import | **Special category (health) + PII** |
| Payment / subscription status | Stripe | Normal (cards never stored locally) |
| Usage & device (IP, referrer, pages, timings, visitor_id) | Visit tracking + GA4 | Normal |

**Sub-processors (all confirmed in code):** Stripe, Supabase, AWS, Anthropic,
OpenAI, Google (OAuth + GA4 `G-JPGJG6GCSK`), Meta, Pinterest, Cloudflare Turnstile.
Several are US-based → GDPR Chapter V transfer obligations apply.

## 2. What this change delivered

Documents are now cohesive, on-brand (`ink`/`parchment`/`paprika`, `font-display`),
cross-linked, and reachable from the landing footer.

| Document | Route | File |
|---|---|---|
| Privacy Policy (full GDPR Art. 13/14 notice) | `/privacy_policy` | `live/privacy_policy_live.ex` |
| Terms of Service | `/terms` | `controllers/terms_html/index.html.heex` |
| Legal Notice / Impressum + sub-processor list | `/legal` | `controllers/legal_notice_html/index.html.heex` |
| Cookie Policy (corrected) | `/cookies` | `controllers/cookies_policy_html/index.html.heex` |

**The one-paragraph privacy policy was replaced.** It previously claimed data was
"not shared with any other party" — affirmatively false (Stripe/Google/Anthropic/etc.
all process data) and a GDPR Art. 5(1)(a) + UCPD problem (audit R7). The Cookie
Policy's identical "we do not share with any third party" line was also corrected and
GA4/Google now disclosed as a US processor (audit R6).

## 3. BEFORE PUBLISHING — operator action items

- [x] Operator details filled: **Nikolaos Galerakis**, individual sole trader, **Kalonykti, Greece**,
      contact **nikolisgal@gmail.com**, not VAT-registered. Governing law / courts: **Greece**;
      lead supervisory authority: **Hellenic DPA (dpa.gr)**.
- [x] Policy decisions applied: honour **14-day withdrawal + refund** (Terms §5); minimum age **16**;
      **not** participating in consumer arbitration (Legal Notice).
- [ ] **Still required:** have a **qualified data-protection / consumer lawyer** review all four
      documents. Disclaimers and notices do **not** by themselves make the underlying processing lawful.

## 3a. Health-claims & health-data exposure REMOVED from the consumer product (2026-10-13)

The end-user health-condition feature — the largest driver of R1 and R3 — was
**deleted from the normal user experience and gated to nutritionists/admins only.**
This is a substantive code change, not a disclaimer.

**Storage removed (R3):** the `user_condition_opt_ins` table is dropped
(migration `20261013150000_drop_user_condition_opt_ins`), the `UserConditionOptIn`
schema and `Accounts.{list_opted_in_condition_ids,set_condition_opt_ins}` are gone.
The app no longer collects or stores any user health-condition data.

**Presentation removed (R1):** `MehungryWeb.RecipeFlags` and the
`condition_flag_badges` component are deleted; condition badges no longer render on
`/foods`, recipe browse, recipe detail, basket, calendar or the ingredient picker;
the public `/:locale/conditions*` pages and the `/foods` "by condition" filter are
removed; the recipe-browser condition filter is removed. On the **mobile API**, the
`/api/v1/conditions*` endpoints, `condition_flags` (recipe/feed), `related_conditions`
(species) and `condition_opt_ins` (me/preferences) are all removed (spec updated).

**Kept, gated ("nutrition gate"):** the `Health` knowledge context and the condition
browsing views remain available only at `/nutritionist/conditions*` (logged-in
nutritionists) and `/professional/health` (admin). A professional using this takes on
the professional-advice responsibility; this does not by itself resolve R1/R2 for the
professional surface — see below.

**Still needs counsel even after this change:**
- R1/R2 for the **nutritionist/admin** surface: condition→food guidance shown to
  professionals still needs a health-claims / medical-device assessment.
- The **meal-blueprint** feature still carries condition labels (e.g. a blueprint tagged
  "IBS") on public surfaces and in `blueprint_match` — assess separately.

## 4. What documents CANNOT fix (still open — needs code and/or counsel)

Writing policies does not close the substantive risks. In rough priority:

1. **Health claims on the professional surface (audit R1, Critical).** The end-user
   exposure is gone (see §3a), but condition→food guidance still shows to nutritionists/
   admins and in meal-blueprint labels. Needs a claims audit against the EU Register and
   rewording/removal for those remaining surfaces.
2. **Medical-device qualification (audit R2, High).** Personalised AI meal plans (and the
   professional condition tooling) risk qualifying as medical-device software
   (MDR 2017/745). Needs a documented non-medical intended-purpose design + a written
   qualification opinion.
3. **Art. 9 health-data basis + DPIA (audit R3, Critical).** End-user condition opt-in
   storage is removed (see §3a). **Remaining:** the nutritionist **client records**
   (`client_intakes`/`consultation_notes`) are still special-category data needing
   explicit-consent capture at intake, a DPA chain, and a DPIA.
4. **Erasure cascade (audit R4, High).** `Accounts.delete_user` omits nutritionist
   client records, intakes, notes, appointments, ratings, articles, dietary history,
   plans, surveys and visit logs; `professional_clients.user_id` is `nilify_all`, so a
   client's health PII survives deletion. Erasure is also a destructive **GET** with a
   misleading "Logged out" flash. Fix the cascade; make it POST + re-auth.
5. **GA loads before consent (audit R6, High).** `gtag.js` is emitted whenever
   `ga_enabled` is true (`head.html.heex:174`), not gated on `cookie_consent == :accepted`.
   Block it until accept; make "Decline" as prominent as "Accept".
6. **Consent at registration (audit R10).** Sign-up is email/password only — no link to
   privacy/terms, no logged consent.
7. **Data export for Art. 15/20 (audit R5).** No access/portability export exists.
8. **AI-content labelling (audit R8).** No end-user "AI-generated" marking (AI Act Art. 50,
   applies 2 Aug 2026).
9. **Subscription withdrawal/VAT transparency (audit R9).** No 14-day withdrawal notice/form;
   confirm Stripe Tax handles EU VAT + invoices.
10. **DSA notice-and-action (audit R11).** No report/flag/takedown flow for UGC. The Legal
    Notice now publishes a contact point, but the in-product mechanism is still missing.

## 5. Recommendation

The four documents remove the most glaring, immediately-actionable exposure (the false
"never shared" statement, missing ToS/Impressum, undisclosed processors). They are
**necessary but not sufficient**. Treat items 1–4 in §4 as blocking before scaling the
health and marketplace features, and route them through counsel.
