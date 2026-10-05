# 03 — EU Compliance Risk Register

> **Preliminary risk analysis, not a formal legal opinion.** Based on a read-only code review plus current EU law (sources accessed 2026-10-05; full list in [file 10](10-sources-and-evidence.md)). The operator is *presumed* EU-established (€ pricing, el/en locales, AWS eu-central-1) — this is an open question that changes several conclusions. Nothing was edited or run. **Disclaimers, consent checkboxes, and privacy policies do not, by themselves, make the underlying processing or claims lawful.**

## The legal surface today

The entire user-facing legal scaffolding is: a **one-paragraph** privacy policy (`privacy_policy_live.ex:14`), a `/cookies` page, and an accept/decline cookie banner. There is **no Terms of Service, no Impressum/legal notice, no operator identity, no processor/sub-processor disclosure, no DSA notice-and-action, no data export, and no consent capture at registration.** Account deletion exists but is incomplete. The product has been built far ahead of its compliance.

## Severity snapshot

| ID | Finding | Regime | Severity | Likelihood | Lawyer? |
|----|---------|--------|----------|-----------|---------|
| R1 | Condition→food guidance = unauthorised health claims | Reg. 1924/2006 | **Critical** | High | **Yes** |
| R2 | Health software may qualify as a medical device | MDR 2017/745 | High | Medium | **Yes** |
| R3 | Special-category health data, no Art. 9 basis / no DPAs | GDPR Art. 9/28/30/35 | **Critical** | High | **Yes** |
| R4 | Incomplete + unsafe right-to-erasure | GDPR Art. 17/12 | High | High | Rec. |
| R5 | No data access/portability export | GDPR Art. 15/20 | Medium | Medium | No |
| R6 | GA loads before consent; non-granular banner | ePrivacy 2002/58 Art. 5(3) | High | High | Rec. |
| R7 | No ToS/Impressum; thin, misleading privacy notice | GDPR Art. 13/14; DSA; e-Commerce | High | High | Rec. |
| R8 | No end-user AI-content labelling; literacy overdue | AI Act Art. 50 / Art. 4 | High | High | Rec. |
| R9 | No 14-day withdrawal / VAT / renewal transparency | CRD 2011/83; UCPD; DCD | High | High | Rec. |
| R10 | No consent/transparency capture at registration | GDPR Art. 7/13 | Medium | Medium | No |
| R11 | No DSA notice-and-action / contact point / trader traceability | DSA 2022/2065 | Med→High | Medium | Rec. |
| R12 | European Accessibility Act exposure | Dir. 2019/882 | Medium | Medium | No* |
| R13 | Marketplace payments: intermediary duties + VAT on fee | CRD/UCPD + VAT | Medium | Medium | Rec. |
| R14 | International transfers to US sub-processors | GDPR Ch. V | Medium | Medium | Rec. |

*\*accessibility audit, not legal, unless scope is contested.*

---

## R1 — Condition→food "recommendations" as unauthorised health claims — **CRITICAL**

- **Feature:** The `Health` context surfaces condition-specific food guidance to end users ("Kidney Stones: avoid Oxalate", "IBS: limit FODMAP", "Anti-Inflammatory") on `/foods`, recipe browse, recipe/ingredient badges, blueprint auto-suggest.
- **Regime:** Nutrition & Health Claims Regulation **(EC) 1924/2006**, Arts. 10–14 — health claims must be authorised / on the EU Register; disease-risk-reduction claims (Art. 14) need individual EFSA authorisation; Art. 12 prohibits certain claim types.
- **Why it applies:** Statements that a food/constituent affects a disease or risk factor are the textbook definition of a health claim (and, tied to a named disease, a disease-risk-reduction claim). Almost none of these condition-specific statements will be on the EU Register.
- **Evidence:** `mehungry/health.ex`, `health/compound_recommendation.ex`, `health/condition_state_recommendation.ex`; surfaced via `RecipeFlags` across `recipe_details_live/`, `shopping_basket_live/`, `condition_detail_live/index.ex`.
- **Gap/risk:** Unauthorised health/disease claims → national food-authority enforcement, forced removal, fines. **A disclaimer does not cure an unauthorised claim** — the Regulation prohibits the claim itself regardless of caveats.
- **Mitigation (substantive):** (a) Legal gap-analysis mapping each surfaced statement to the EU Register; remove/rephrase anything unauthorised. (b) Separate *authorised nutrient* claims (which exist on the Register) from *condition* claims (which generally don't). (c) Consider reframing from directive advice ("avoid X for disease Y") to neutral, sourced scientific information positioned clearly outside commercial communication — and have counsel confirm that boundary. (d) Do not rely on "informational only" as a defence.
- **Severity** Critical · **Likelihood** High · **Uncertainty** Medium (turns on whether the output is treated as commercial communication/food information vs pure editorial). **Specialist review required.**

## R2 — Health software as a potential Medical Device (MDSW) — **HIGH**

- **Feature:** Software linking a self-declared condition to foods to favour/avoid; AI meal-plan and nutritionist agents generating personalised dietary plans.
- **Regime:** MDR **(EU) 2017/745** Art. 2(1) + Annex VIII **Rule 11**; qualification guidance **MDCG 2019-11**.
- **Why it applies:** Qualification turns on *intended purpose*. Software intended to diagnose, monitor, treat, alleviate or **prevent** disease is MDSW; information for therapeutic decisions starts at Class IIa. Condition-badge opt-in + personalised plans move the product from "general wellness" toward "managing a specific condition."
- **Evidence:** `UserProfile` condition opt-in; `ai/agents/meal_plan_agent.ex`, `ai/agents/nutritionist_agent.ex`; `RecipeFlags.opted_in_condition_ids/1`.
- **Gap/risk:** If the intended purpose is medical, this is an unregistered medical device (no CE mark, QMS, or clinical evaluation). **Disclaimers do not determine qualification** — stated/implied intended purpose and actual functionality do.
- **Mitigation:** Deliberately engineer and *document* a non-medical intended purpose (general wellness/lifestyle); avoid individualised therapeutic recommendations tied to a diagnosis; obtain a written qualification opinion. Note R1 and R2 pull opposite ways — more disease-specific wording worsens both; resolve holistically.
- **Severity** High · **Likelihood** Medium · **Uncertainty** High (fact/wording-dependent). **Specialist review required.**

## R3 — Special-category health data with no Art. 9 basis or DPA chain — **CRITICAL**

- **Feature:** Nutritionist client records (anthropometrics, BMI/BMR/TDEE, goals, free-text medical details); user health-condition opt-in badges.
- **Regime:** GDPR **Art. 9** (processing prohibited absent an exception — usually explicit consent or Art. 9(2)(h) health-care provision), **Art. 6**, **Art. 28** (processor contracts), **Art. 13/14**, **Art. 30**, **Art. 35** (DPIA).
- **Why it applies:** `client_intakes` and the condition opt-in are "data concerning health." No explicit-consent capture, no Art. 9 condition identified anywhere in code or policy, no DPA/sub-processor disclosure, no retention rule.
- **Evidence:** `professionals/client_intake.ex:25-41` (height, weight, bmi, bmr, tdee, goal, details map); `professionals/consultation_note.ex`; `professionals/dietary_history/` CSV importer; `UserProfile` condition opt-in; `privacy_policy_live.ex:14` (one paragraph, no Art. 9/lawful-basis/retention content).
- **Gap/risk:** No valid Art. 9 basis = unlawful processing of the most sensitive data category; controller/processor roles between platform and nutritionist are undefined (joint controllers? processor?).
- **Mitigation:** Define and paper controller/processor roles (Art. 26/28); capture **explicit, specific, withdrawable** health-data consent at intake and at condition opt-in; add a retention schedule; write a real Art. 13/14 notice; build Art. 30 records; run a **DPIA** (large-scale special-category processing is a mandatory trigger).
- **Severity** Critical · **Likelihood** High · **Uncertainty** Medium (controller vs processor changes who owes what). **Specialist review required.**

## R4 — Incomplete / mislabelled right-to-erasure — **HIGH**

- **Feature:** Self-service "Delete Account."
- **Regime:** GDPR **Art. 17** (erasure), **Art. 12** (transparent, user-friendly rights exercise).
- **Why it applies:** Erasure must be complete and the mechanism clear. The cascade deletes recipes/comments/votes/baskets/profile but **omits** `professional_clients`, `client_intakes`, `consultation_notes`, `appointments`, `meal_plan_ratings`, articles, `dietary_history`, `Plans`, `Survey`, and `Meta` visit logs — i.e. it leaves the health PII behind. It is also a destructive **GET** with no re-authentication and a **misleading flash** ("Logged out successfully").
- **Evidence (verified by this audit):** route `get "/users/delete"` (`router.ex:435`) → `user_session_controller.ex:38` → `user_auth.ex:80` → `Accounts.delete_user` cascade (`accounts/admin.ex:137-217`). The `professional_clients.user_id` FK is `on_delete: :nilify_all` (`migrations/20260904000001`), so a deleting client's health record is merely **de-linked, not erased** — identifiable `full_name`, `date_of_birth`, `email`, `phone`, `address` + cascading intakes/notes survive.
- **Mitigation:** Extend the cascade to every table holding the user's personal/health data (or anonymise where a legal retention basis genuinely applies — Art. 17(3)); change erasure to **POST with re-auth** + accurate confirmation copy; add a deletion runbook that also removes/anonymises data at processors (Stripe).
- **Severity** High · **Likelihood** High · **Uncertainty** Low. **Review recommended.**

## R5 — No data portability / access export — **MEDIUM**

- **Regime:** GDPR **Art. 20** (portability), **Art. 15** (access). No export route/function found.
- **Gap/risk:** Cannot satisfy access/portability within the one-month deadline.
- **Mitigation:** Build a self-service or ops-supported export (JSON/CSV) covering profile, recipes, meal plans, history; document an SAR workflow with the one-month clock. **Severity** Medium · **Likelihood** Medium · **Uncertainty** Low. Standard build.

## R6 — Google Analytics loaded before consent; non-granular banner — **HIGH**

- **Feature:** GA4 gtag.js with Consent Mode v2 default-denied; binary accept/decline banner.
- **Regime:** ePrivacy Directive **2002/58** Art. 5(3) (prior informed consent for non-essential storage/access) + GDPR consent standard; EDPB Guidelines 05/2020.
- **Why it applies:** The `gtag/js` tag is emitted (and sends cookieless pings to Google) whenever `ga_enabled` is true — i.e. **before** the user accepts. Consent Mode "denied" avoids writing `_ga`/`_gid` cookies but **still loads a US third-party script and transmits data**; regulators treat Consent Mode as *not* a substitute for prior blocking.
- **Evidence:** `head.html.heex:71` (`ga_consent_granted`), `:87-88` (`ga_enabled`), `:174-186` (gtag.js emitted under `ga_enabled`, not consent); consent stored as a single accepted/declined value (`plugs/cookie_consent.ex`). jQuery is also loaded from `code.jquery.com` (`head.html.heex:167`) — a third-party request (IP leak) on every page. **Clarification:** the `...@facebook.user` string at `head.html.heex:81` is a Facebook-OAuth-derived email in the GA *exclusion* list — **not** a Meta Pixel. No Meta tracker is loaded.
- **Mitigation:** Do not emit gtag.js until `cookie_consent == :accepted`; make "Reject" as prominent/easy as "Accept"; disclose GA (Google as processor + US transfer) in the cookie/privacy policy; consider self-hosting jQuery.
- **Severity** High · **Likelihood** High · **Uncertainty** Low-Medium. Review recommended.

## R7 — No ToS, no Impressum, thin & misleading privacy notice — **HIGH**

- **Regime:** GDPR **Art. 13/14**; **DSA Art. 14** (clear T&Cs) + Arts. 11–13 (contact/legal rep); national e-commerce/imprint duties (e-Commerce Dir. 2000/31 Art. 5).
- **Why it applies:** A commercial platform must identify its operator and provide the Art. 13 information set. The current notice omits controller identity, legal bases, processors (Anthropic, OpenAI, Stripe, AWS, Google, Ueberauth), transfers, retention, and rights.
- **Evidence:** `privacy_policy_live.ex:14` — single paragraph that **inaccurately states data is never shared "with any other party"** while Stripe/AWS/Anthropic/OpenAI/Google all process data; no ToS/Impressum routes (`router.ex` has only `/privacy_policy`, `/cookies`); registration template has only email/password.
- **Gap/risk:** Transparency failures; the "not shared with any other party" sentence is affirmatively **misleading** (GDPR Art. 5(1)(a) + UCPD).
- **Mitigation:** Publish a full Art. 13/14 privacy notice (real processor list + transfer mechanisms + retention + rights), a ToS, and an operator Impressum; add transparency at registration; **correct the false "never shared" statement immediately.**
- **Severity** High · **Likelihood** High · **Uncertainty** Low. Review recommended.

## R8 — EU AI Act transparency & literacy — **HIGH (deadline imminent)**

- **Feature:** AI-generated recipes, AI cover images, AI meal plans, "nutritionist agent."
- **Regime:** AI Act **(EU) 2024/1689** **Art. 50** (AI-interaction disclosure + marking of synthetic content; applies **2 Aug 2026**) and **Art. 4** (AI-literacy duty, in force since **2 Feb 2025**).
- **Why it applies:** As deployer (and, for its own agent configs, arguably provider) of generative AI, the operator must mark AI-generated content and disclose AI interaction.
- **Evidence:** "AI-generated" label appears **only in the admin review queue** (`ai_bot_live/review_queue.ex:222`); no end-user AI labelling found anywhere in `live/` or `components/`. Published bot recipes/images carry no user-visible AI marking.
- **Mitigation:** Add visible "AI-generated" labelling to published AI recipes/images + an AI-interaction notice on any conversational agent; implement machine-readable marking per the finalised EC guidelines; put a basic staff AI-literacy measure in place now. The health-advice AI also needs an AI Act **risk-classification** check.
- **Severity** High · **Likelihood** High · **Uncertainty** Medium (provider vs deployer; marking technique still being finalised). Review recommended.

## R9 — Consumer subscription: no withdrawal right / VAT / renewal transparency — **HIGH**

- **Feature:** Paid digital subscriptions (Plus €9.99/€99; Pro €29.90/€290) via Stripe; "Cancel anytime."
- **Regime:** Consumer Rights Directive **2011/83/EU** (pre-contractual info Art. 6; 14-day withdrawal Art. 9; digital-content waiver Art. 16(m)); CJEU **C-234/25** (personalised subscriptions are digital *services* → upfront waiver cannot extinguish withdrawal); UCPD **2005/29**; Digital Content Directive **2019/770**.
- **Evidence:** `upgrade_live/index.ex:10-19` (display-only prices); `stripe_handler.ex` activates on `checkout.session.completed`; **no** withdrawal notice, model form, VAT breakdown, or renewal reminder found.
- **Mitigation:** Add CRD Art. 6 pre-contractual disclosures + a 14-day withdrawal notice/model form to the upgrade flow; implement withdrawal/pro-rata refund *or* a valid explicit immediate-performance consent flow; confirm Stripe Tax handles EU VAT + compliant invoices; show gross price incl. VAT; add renewal reminders.
- **Severity** High · **Likelihood** High · **Uncertainty** Medium (whether Stripe Tax already covers VAT — unverifiable from code). Review recommended.

## R10 — No consent/transparency capture at registration — **MEDIUM**

- **Regime:** GDPR Art. 7/13; EDPB 05/2020. Sign-up form is email/password only (`templates/user_registration/new.html.heex`); no consent handling in the controller (Turnstile only).
- **Mitigation:** Show + link the privacy notice/ToS at sign-up; capture any required consents as separate, logged, affirmative actions (timestamp + version); keep health-data consent (R3) distinct from a blanket "I agree." **Severity** Medium · **Likelihood** Medium · **Uncertainty** Low.

## R11 — DSA: no notice-and-action, contact point, or trader traceability — **MEDIUM→HIGH (size-dependent)**

- **Feature:** UGC (recipes, comments, votes, profiles) = hosting; nutritionist marketplace = online marketplace.
- **Regime:** DSA **(EU) 2022/2065** — hosting **Art. 16** notice-and-action, Arts. 11–13 contact/legal rep, **Art. 14** T&Cs; marketplace **Art. 30** trader traceability. **Art. 29** exempts *online-platform-tier* duties for enterprises <50 staff & <€10m turnover, **but hosting-tier duties still apply regardless of size.**
- **Evidence:** No report/flag/takedown mechanism (grep hits only `RecipeFlags` = health badges); no abuse/contact route; nutritionist profiles + Connect exist but no trader-identity collection/verification/publication.
- **Mitigation:** Build an Art. 16 notice-and-action flow + reasoned-decision/appeal path; publish a point of contact (and EU legal rep if no EU establishment); meet Art. 14 T&Cs; collect/verify/publish trader identity (Art. 30) if above threshold. **Confirm enterprise size** to fix the tier.
- **Severity** Medium (likely small today) → High if ≥50 staff/≥€10m · **Likelihood** Medium · **Uncertainty** High. Review recommended after confirming size.

## R12 — European Accessibility Act — **MEDIUM**

- **Regime:** Directive **(EU) 2019/882** (applies **28 June 2025**); e-commerce consumer services in scope (EN 301 549/WCAG); **micro-enterprise exemption for *services*** (<10 staff AND ≤€2m).
- **Evidence:** `outline:none` on all focusable elements (`head.html.heex:157-164`) removes visible keyboard focus — a concrete WCAG 2.4.7 failure; no accessibility statement.
- **Mitigation:** Confirm micro-enterprise status; if in scope, run a WCAG 2.1 AA audit, restore visible focus styles, publish an accessibility statement. Restoring focus is good practice regardless. **Severity** Medium · **Likelihood** Medium (hinges on size) · **Uncertainty** Medium.

## R13 — Marketplace payments: intermediary duties + VAT on the fee — **MEDIUM**

- **Regime:** CRD/UCPD intermediary information duties; EU VAT on any platform commission; overlaps DSA Art. 30 (R11); professional-regulation liability for nutritionist advice.
- **Evidence:** `professional_profile.ex:35` (`stripe_charges_enabled`), `:91` (`stripe_connect_account_id`); `professionals.ex:63-67` webhook helper. **The audit confirmed there is currently no charge/`application_fee`/capture code and no `professional_payments` ledger** — the booking-payment flow is **not implemented**. So this risk is *latent*: it bites only once booking payments are built. When built, it needs VAT on the commission, intermediary disclosures, and a liability/indemnity split with nutritionists.
- **Severity** Medium (latent) · **Likelihood** Medium · **Uncertainty** High (flow not built). Review recommended before launching paid bookings.

## R14 — International transfers to US sub-processors — **MEDIUM**

- **Regime:** GDPR **Ch. V** (Arts. 44–49); EU-US Data Privacy Framework (adequacy 2023, under challenge) and/or SCCs + transfer impact assessments.
- **Evidence:** Anthropic (`ai/client.ex`), OpenAI, Stripe (`billing/stripe_handler.ex`), AWS (`s3.ex`), Google/Meta OAuth — all US-based; health data may flow to US AI providers.
- **Mitigation:** Inventory each processor; confirm DPF certification or execute SCCs + TIA; ensure no special-category data reaches AI providers without a basis; disclose transfers in the privacy notice (R7). **Severity** Medium · **Likelihood** Medium · **Uncertainty** Medium. Review recommended.

---

## Prioritized compliance action plan

**Phase 0 — Immediate (days), low effort / high exposure**
1. Stop emitting GA gtag.js before consent; make "Reject" equal to "Accept" (R6).
2. Correct the false "data not shared with any other party" sentence (R7).
3. Fix the deletion cascade to cover health-PII tables; change destructive GET → POST + accurate confirmation (R4).
4. Put a basic AI-literacy measure in place for staff — overdue since Feb 2025 (R8/Art. 4).

**Phase 1 — Short term (2–6 weeks)**
5. Publish a full Art. 13/14 privacy notice (+ processors/transfers/retention/rights), a ToS, an Impressum, and a DSA point of contact (R7, R11).
6. Build Art. 16 notice-and-action + reporting UI for UGC (R11).
7. Add CRD pre-contractual info + 14-day withdrawal notice/form; confirm Stripe Tax VAT + invoicing (R9).
8. Add user-visible "AI-generated" labelling + AI-interaction notices (R8).
9. Capture explicit, unbundled health-data consent at intake/condition opt-in; add registration transparency (R3, R10).
10. Build data export for Art. 15/20 + a documented SAR/erasure workflow (R5).

**Phase 2 — Structural / needs counsel (6–12 weeks)**
11. **Health-claims audit** of every condition→food statement against the EU Register; remove/rephrase unauthorised claims (R1). *Highest legal priority.*
12. **MDSW qualification opinion** + deliberate non-medical intended-purpose design (R2).
13. **DPIA** + controller/processor role definition + Art. 28 DPAs with all processors + Ch. V transfer mechanisms (R3, R14).
14. Confirm enterprise size → scope DSA Art. 30 + EAA; WCAG audit if in scope (R11, R12).
15. VAT + intermediary-liability structuring before launching paid bookings (R13).

## Open legal questions

See [file 09](09-open-questions-and-assumptions.md) — the operating entity/establishment, enterprise size, platform-vs-processor role for client records, whether the condition→food feature is "commercial communication", the AI's intended purpose, and whether Stripe Tax handles VAT all materially change these conclusions.

**Bottom line:** The gravest exposures are substantive (R1/R2 health-claims/medical-device, R3/R4 unlawful health-data posture) and **none can be fixed with a disclaimer.** The existing disclaimers, cookie banner, and delete button create an *appearance* of compliance that does not hold up. Treat R1, R2, and R3 as blocking before scaling the health/marketplace features.
