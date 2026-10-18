# Growth Plan — Oct 17 → Nov 14, 2026

**Baseline source:** [docs/app_status.md](app_status.md) (snapshot 2026-10-17)
**Cadence:** review every Friday against the weekly sprint; append the Week-4 retro here and a
new row to [app_status.md §6](app_status.md#6-snapshot-log).

**Thesis:** At ~4 signups/mo with a 98%-Greece, Crete-heavy audience and near-zero
engagement, the win is un-scalable founder work — manually recruit + activate the first
~100 real users where they physically are (Crete), in Greek, while seeding the one channel
that compounds (SEO). **No paid ads this month.** Don't pour into a leaky bucket: fix the
signup→confirm leak and activation *before* scaling acquisition.

---

## Month targets (Oct 17 → Nov 14)

| # | Metric | Baseline | Target | Floor | Measured by |
|---|---|---:|---:|---:|---|
| 1 | New registered users /month | 4 | 30 | 20 | `users_new_30d` ([§5.1](app_status.md#51-current-queries-while-the-visits-table-still-exists--pre-deploy)) |
| 2 | Confirmation rate on this month's signups | 33% | ≥55% | 45% | confirmed ÷ new (`users`) |
| 3 | Activation: % of new signups w/ ≥1 real action (save / meal-plan / follow) in 7d | ~0% | ≥40% | 30% | join `users`→`user_recipes`/`meal_plans`/`user_follows` |
| 4 | User-created weekly meal plans (non-owner) | 0 | ≥5 | 3 | `meal_plans_total` |
| 5 | Real engagement actions from non-owner users | 34 ever | +25 | +15 | comments+likes+saves+follows delta |
| 6 | SEO seeded | n/a | sitemap submitted + `/foods` indexed + first GSC impressions >0 | sitemap submitted | Search Console |
| 7 | Partnership landed (nutritionist/creator actively using) | 0 | 1 | 0 (1 convo) | manual |

> Targets **3 & 4 matter more than target 1** — a month of passive signups is worse than
> fewer activated users. Optimise for activated users, not raw signups.

---

## Weekly sprints

### Week 1 (Oct 17–23) — Plug the bucket + arm the surfaces
*Don't acquire yet; make sure what you acquire sticks and is trackable.*

**Targets:** +5 signups (warm network only), ≥50% confirm on them, funnel instrumented, SEO submitted.

- **Fix the signup→confirm leak** (see the Week-1 engineering checklist below — deliverability
  audit + copy fix + Greek email + resend discoverability). Highest-ROI task of the month.
- Submit `/foods` + `/el` sitemap to Google Search Console; request indexing; verify
  hreflang/canonical.
- Ship + dogfood the weekly-program share; add the "Made with m3hungry" referral footer so
  every shared plan links back.
- Baseline post-deploy metrics: confirm `daily_session_metrics` is filling; capture the GA4
  28-day baseline ([§5.3](app_status.md#53-ga4-pull-by-hand)).
- Personally invite ~10 from your network; watch them activate.

### Week 2 (Oct 24–30) — Hyperlocal launch (Crete offline + Greek communities)
*Go where 98% of them already are.*

**Targets:** +10 signups, ≥40% activate, 1 partner conversation started.

- **Offline Crete:** QR "free weekly Mediterranean/Cretan meal plan" cards at University of
  Crete / ΕΛΜΕΠΑ boards, a λαϊκή αγορά stall (Rethymno/Heraklion), 1 gym/yoga studio. QR →
  the share landing, not the homepage.
- **Greek online, value-first:** one useful post in 3–5 large Greek cooking FB groups +
  r/greece / r/greekfood sharing a `/foods` page (useful + a backlink). Not spam.
- **Start partner outreach:** DM 3–5 Greek dietitians — pitch = free Pro + their
  client-records workspace.

### Week 3 (Oct 31–Nov 6) — Partnerships + content + double down
*Leverage (one partner = many users) and compounding content.*

**Targets:** +10 signups, land 1 nutritionist partner, ≥3 shared weekly plans.

- **Close 1 nutritionist** and onboard to client-records → their clients become users (B2B2C
  beats one-by-one).
- Publish **2–3 Greek cornerstone pieces** via the Articles feature targeting long-tail Greek
  searches ("εβδομαδιαίο πρόγραμμα διατροφής", "μεσογειακή διατροφή συνταγές").
- **Kill/scale:** do more of whatever Week-2 channel produced *activators*; drop
  passive-signup channels.
- **Activation push:** email the month's signups "build + export your first weekly plan in 2
  min". Target ≥3 shared plans.

### Week 4 (Nov 7–14) — Retain, close the loop, measure
*Turn signups into the loyal core; decide next month from evidence.*

**Targets:** +5 signups (compounding), hit #3 ≥40% and #4 ≥5, publish snapshot.

- Personally message stalled signups ("what stopped you?") — reactivation + qualitative data.
- Post the AI recipe social-graphics from the week's best recipes to IG/Pinterest/FB.
- Run [§5.1](app_status.md#51-current-queries-while-the-visits-table-still-exists--pre-deploy)/[§5.2](app_status.md#52-post-deploy-queries-after-the-analytics-removal-branch-ships)
  queries + GA4, append the [app_status.md §6](app_status.md#6-snapshot-log) snapshot row,
  write a 5-line retro (best activated-user cost per channel; kill/2× decisions).

---

## Week-over-week watch list

1. **New users /30d** — trickle turning into a trend, or still flat?
2. **Organic** — GSC impressions on `/foods` (currently zero; the #1 compounding unlock).
3. **Activation %** — are new users doing ≥1 real action?
4. **Meal plans created** — the loop proof (baseline 0).
5. **Confirmation rate** — did the Week-1 funnel fix move it off 33%?

---

## Week 1 engineering checklist (funnel-fix)

Tracked in code. `[code]` = app change, `[ops]` = DNS/Mailgun console (human-applied).

### A. Confirmation-email deliverability + funnel
- **A1 [ops]** Audit SPF/DKIM/DMARC on `m3hungry.com` for **Mailgun EU**; confirm the domain
  is verified (not sandbox); score a test send on mail-tester.com (≥9) and confirm Gmail
  Primary placement. Sender: `noreply@m3hungry.com`.
- **A2 [code]** Registration no longer swallows the deliver result — a Mailgun failure
  surfaces a resend path to the user and is logged with its reason.
- **A3 [code]** Confirmation email expiry copy corrected to **7 days** (matches
  `@confirm_validity_in_days`).
- **A4 [code]** Confirmation email **localized to Greek** (`el`), switched on user locale.
- **A5 [code]** "Resend confirmation" link surfaced from the registration success flash and
  the login page (→ `/users/confirm`).
- **A6 [code, optional]** Auto-login on confirm → straight into onboarding (removes a
  dead-end step).

### B. Weekly-program referral footer
- **B1 [code]** "Made with m3hungry.com" footer + link on the public blueprint share page
  (`/blueprints/:slug`).
- **B2 [code]** Open Graph / Twitter-card meta on `/blueprints/:slug` for a rich FB/Pinterest
  unfurl.
- **B3 [code, deferred]** When the image/PDF export artifact lands, bake the brand lockup in
  by reusing `MehungryWeb.InsightGraphic.wordmark/0` (vix/SVG pattern) — not a new convention.
