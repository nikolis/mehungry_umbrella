# App Status — Usage, Users & Engagement

**Snapshot date:** 2026-10-17
**Sources:** production Supabase DB (direct SQL) + Google Analytics 4 (GA4) + the legacy `visits` table.
**Cadence:** re-run the queries in [§5 How this is measured](#5-how-this-is-measured) roughly weekly and append a new row to [§6 Snapshot log](#6-snapshot-log).

> ⚠️ **Read this first — the measurement method is about to change.** The custom
> server-side analytics (the `visits` table and its dashboards) is being removed in
> favour of GA4 + Search Console. Once the current branch deploys:
> - the `visits`-based numbers below (traffic, geography, top pages) **can no longer be
>   re-queried** — the table is dropped;
> - a new consent-independent `daily_session_metrics` table starts filling.
>
> So for next week's snapshot, use the **post-deploy** queries in §5.2, not the `visits` ones.

---

## 1. TL;DR

- **Tiny but real.** 49 registered users total, 16 email-confirmed (33%). Only ~4 new users in the last 30 days.
- **One-off growth spike, no engine.** 27 of the 49 signups (55%) landed in a single month (2026-07); every other month is 1–7. No sustained acquisition.
- **Content is mostly automated.** 85 recipes but only **5 distinct authors** (dominated by the AI bot + owner), and 483 posts (posts ≈ recipes × languages + bot social posts).
- **Human engagement ≈ zero.** Across 483 posts: **1 comment, 0 likes**, 25 recipe saves, 8 follows, 0 user meal-plans.
- **Audience is Greece, and tiny.** 98.3% of *geolocated* traffic is Greece (Crete-heavy); only **114 distinct IPs over 5 months** (4,203 visits since 2026-05-19, 411 in the last 30 days); GA4 ≈ 150 sessions/month; **zero organic search** so far.
- **Social is dormant.** Facebook Page: **0 followers**, 0 engagement (117 views/28d). Pinterest: 73 impressions but audience of 1 and only **3 outbound clicks/30d**. Neither drives acquisition.
- **Verdict:** the product works and has a (very) small loyal Greek core, but it is pre-traction: acquisition and engagement are both near-zero. The lever is organic-traffic growth, not monetisation. See [[project_audience_ads_viability]] in memory.

---

## 2. Users & growth

| Metric | Value | Notes |
|---|---:|---|
| Registered users (total) | **49** | |
| Email-confirmed | **16** | 33% confirmation rate — most signups never confirm |
| New users (last 30 days) | **4** | |
| Completed onboarding (`onboarding_level > 0`) | **15** | ~31% of users finished the wizard |
| Has a diet set | 49 | Not a useful signal — `diet` is defaulted for everyone |

**Signups by month** (all-time):

| Month | Signups |
|---|---:|
| 2025-03 | 2 |
| 2025-06 | 2 |
| 2025-11 | 1 |
| 2026-05 | 2 |
| 2026-06 | 7 |
| 2026-07 | **27** ← spike (beta/campaign push) |
| 2026-08 | 4 |
| 2026-09 | 2 |
| 2026-10 | 2 (partial month) |

Read: a ~19-month trickle, one big spike in July 2026, then back to baseline. The spike did not convert into retained growth.

---

## 3. Content & engagement

| Metric | Value | Notes |
|---|---:|---|
| Recipes (total) | **85** | |
| Distinct recipe authors | **5** | Mostly the AI bot + owner; ~10% of users have ever authored |
| New recipes (last 30 days) | 4 | |
| Posts (total) | **483** | One post per recipe × language + AI-bot social posts — not 483 distinct user actions |
| Comments | **1** | |
| Likes (`post_upvotes`) | **0** | |
| Recipe saves (`user_recipes`) | 25 | |
| Follows (`user_follows`) | 8 | |
| User meal plans | **0** | |
| Beta signups (`beta_signups`) | 0 | |

Read: supply (recipes/posts) is almost entirely machine-generated; demand-side engagement (comments, likes, saves, follows, meal plans) is effectively nil. The social loop is not turning yet.

---

## 4. Traffic & geography

> Source: legacy `visits` table (consent-gated, LiveView-only — it **undercounts**: it only
> records visitors who accepted the cookie banner, on LiveView page loads) + GA4. Rows marked
> *(live 2026-10-17)* were queried directly; *(memory 2026-10-17)* figures are from the prior
> capture and still need a live refresh. After the branch deploys, `visits` is gone → use GA4.

| Metric | Value | Source |
|---|---:|---|
| Tracked visits (all-time) | **4,203** | `visits` *(live 2026-10-17)* |
| Tracking window | 2026-05-19 → 2026-10-17 (~5 months) | `visits` *(live)* |
| Distinct IPs (all-time) | **114** | `visits` *(live)* — a hard ceiling on real reach |
| Visits (last 30 days) | **411** | `visits` *(live)* |
| GA4 sessions / month | ~150 | GA4 *(memory 2026-10-17)* |
| Share from Greece (of geolocated) | **98.3%** (2,140 / 2,176) | `visits` *(live)* — see country table |
| Organic-search sessions | **0** | GA4 acquisition + `visits` referrers *(memory 2026-10-17)* |
| Real human hot-spots | Crete (Rethymno / Heraklion / Ierapetra) | GA4 geo *(memory 2026-10-17)* |

**Country breakdown** (all-time, from `visits`, live 2026-10-17):

| Country | Visits |
|---|---:|
| Greece (GR) | 2,140 |
| *(unknown — un-geolocated)* | 2,027 |
| United States (US) | 26 |
| Sweden (SE) | 7 |
| Ireland (IE) | 2 |
| Netherlands (NL) | 1 |

Read: ~48% of rows have no country — those are private/local IPs (owner/dev traffic) plus
rows the old enrichment bug never backfilled. Among the **2,176 geolocated** visits, Greece is
**98.3%**; the non-GR remainder (36 visits) is mostly datacentre/scraper noise. Net: the real
human audience is Greece, and 114 distinct IPs over 5 months is the true reach ceiling.

**Traffic sources (acquisition channel):** _not tracked server-side._ The old `visits`
referrer data was deliberately **not** used here — referrers are unreliable (browsers strip
them; in-app Instagram/Facebook/Pinterest browsers send none, so social traffic misreports as
"direct"), the app pollutes its own referrer via LiveView navigation, and it's consent-gated +
non-reproducible after deploy. **Source of truth = GA4 → Acquisition → Traffic acquisition
(by channel).** _To fill: Direct / Organic Search / Organic Social / Referral — pull from GA4
(last 28 days)._

**Social reach** (off-site, from each platform's own dashboard, 2026-10-17; manual pull —
automation path in §7.3–7.4):

| Channel | Metric | Value | Window |
|---|---|---:|---|
| Facebook Page | Followers | **0** | lifetime |
| Facebook Page | Views | 117 | 28d |
| Facebook Page | Content engagement | **0** | 28d |
| Pinterest | Impressions | 73 | 30d |
| Pinterest | Engagements | 12 | 30d |
| Pinterest | Outbound clicks (→ site) | **3** | 30d |
| Pinterest | Saves | 0 | 30d |
| Pinterest | Total / engaged audience | 1 / 1 | 30d |

Read: both channels are **dormant**. Facebook has 0 followers and 0 engagement — the Page
exists but has no audience. Pinterest shows a faint pulse (the AI-bot auto-posts generate ~73
impressions) but essentially no audience (1) and only **3 outbound clicks to the site in 30
days** — i.e. social sends virtually zero referral traffic. Social is not an acquisition
channel today.

**Top pages** (all-time, from `visits`, captured 2026-10-17):

| Page | Views |
|---|---:|
| /home | 1077 |
| /profile | 517 |
| *(blank / untracked)* | 349 |
| /create_recipe | 313 |
| /browse | 278 |
| /el/home | 239 |
| /en/home | 150 |
| /calendar | 111 |
| /el/profile | 76 |
| /el/browse | 71 |
| /el/create_recipe | 66 |
| /share_social_media/67/pinterest | 46 |

Read: `/home` → `/profile` → `/create_recipe`/`/browse` is the core loop. The Greek locale (`/el/*`) out-draws English (`/en/*`) ~239 vs ~150, confirming the Greece-first audience.

### 4.5 Organic search / SEO (2026-10-19)

Deep SEO read via the GSC Search-Analytics pull + URL Inspection API + a Lighthouse snapshot — **full detail and the prioritized actions live in `docs/seo.md` (see its dated "SEO snapshot — 2026-10-19" section)**. Headlines:

- **Organic is starting and improving.** 28d vs prior 28d: clicks 7→**13**, CTR 0.38%→**1.57%**, avg position **50.1→12.6** (page 5 → page 1–2). Impressions fell 1,824→828 but that was junk position-~50 noise dropping off — net quality up.
- **Lighthouse (mobile): SEO 100 / Best Practices 100**, Accessibility 84 (contrast on hashtag chips + the cookie "Accept" button, a few unnamed controls — fixes listed in `seo.md`).
- **URL Inspection:** key pages PASS/indexed. Fixed the **Recipe structured-data** warnings (added per-serving `nutrition`, `totalTime`, `datePublished`, step `name` fallback). Open: Greek `/foods` pages lose to **duplicate-canonical** (Google folds `/foods/Κάρδαμο` into `/foods/Cress`).
- **🚫 Condition pages (`/conditions/:id`) removed from the roadmap (2026-10-19).** Condition-targeted dietary advice makes the app a **regulated medical device** (EU MDR / SaMD) we can't support now. The condition-query cluster — which the data flagged as the biggest ranking opportunity — is therefore **not** being pursued. See the notice in `docs/seo.md`.

---

## 5. How this is measured

All numbers come from **production**. Two ways to run the SQL:

- **Easiest:** Supabase dashboard → SQL Editor (set "No limit") → paste a block → read the result.
- **From a shell with prod access:** `fly ssh console` then `/app/bin/mehungry eval "…"`, or psql with the prod `DATABASE_URL`. (Prod reads are permission-gated in the agent harness, so these are typically run by a human.)

GA4 is **not** queryable from the codebase (no Analytics Data API credential is configured —
the app only *sends* events via gtag). Pull GA4 figures by hand from the GA4 UI (see §5.3).

### 5.1 Current queries (while the `visits` table still exists — pre-deploy)

**Users + engagement** (one row):

```sql
SELECT
  (SELECT count(*) FROM users)                                              AS users_total,
  (SELECT count(*) FROM users WHERE confirmed_at IS NOT NULL)               AS users_confirmed,
  (SELECT count(*) FROM users WHERE inserted_at > now() - interval '30 days') AS users_new_30d,
  (SELECT count(*) FROM user_profiles WHERE onboarding_level > 0)           AS profiles_onboarded,
  (SELECT count(*) FROM user_profiles WHERE diet IS NOT NULL AND diet<>'')  AS profiles_with_diet,
  (SELECT count(*) FROM recipes)                                            AS recipes_total,
  (SELECT count(DISTINCT user_id) FROM recipes)                            AS recipe_authors,
  (SELECT count(*) FROM recipes WHERE inserted_at > now() - interval '30 days') AS recipes_new_30d,
  (SELECT count(*) FROM posts)                                              AS posts_total,
  (SELECT count(*) FROM comments)                                           AS comments_total,
  (SELECT count(*) FROM post_upvotes)                                       AS likes_total,
  (SELECT count(*) FROM user_recipes)                                       AS recipe_saves,
  (SELECT count(*) FROM user_follows)                                       AS follows_total,
  (SELECT count(*) FROM meal_plans)                                         AS meal_plans_total,
  (SELECT count(*) FROM beta_signups)                                       AS beta_signups;
```

**Signups by month:**

```sql
SELECT to_char(date_trunc('month', inserted_at),'YYYY-MM') AS month, count(*) AS signups
FROM users GROUP BY 1 ORDER BY 1;
```

**Traffic totals** (consent-gated undercount — see §4 caveat):

```sql
SELECT
  (SELECT count(*) FROM visits)                                                AS visits_total,
  (SELECT min(inserted_at)::date FROM visits)                                  AS first_visit,
  (SELECT max(inserted_at)::date FROM visits)                                  AS last_visit,
  (SELECT count(DISTINCT ip_address) FROM visits)                              AS distinct_ips,
  (SELECT count(*) FROM visits WHERE inserted_at > now() - interval '30 days') AS visits_30d;
```

**Top countries / top pages:**

```sql
SELECT COALESCE(details->>'country','(unknown)') AS country, count(*) AS c
FROM visits GROUP BY 1 ORDER BY c DESC LIMIT 12;

SELECT COALESCE(details->>'path','/') AS path, count(*) AS c
FROM visits GROUP BY 1 ORDER BY c DESC LIMIT 12;
```

### 5.2 Post-deploy queries (after the analytics-removal branch ships)

The `visits` table is gone; `users` / `recipes` / `posts` / engagement queries in §5.1 are
unchanged. For traffic, the only in-DB signal is the consent-independent session counter:

```sql
-- anonymous, consent-independent sessions (the "true denominator" GA4 can't see)
SELECT
  COALESCE(sum(session_count),0)                               AS sessions_total,
  min(date)                                                    AS first_day,
  max(date)                                                    AS last_day,
  CASE WHEN sum(session_count) > 0
       THEN round(sum(total_duration_seconds)::numeric / sum(session_count))
       ELSE 0 END                                              AS avg_session_seconds
FROM daily_session_metrics;

-- last 14 days, per day
SELECT date, session_count,
       CASE WHEN session_count > 0
            THEN round(total_duration_seconds::numeric / session_count) ELSE 0 END AS avg_seconds
FROM daily_session_metrics
WHERE date >= current_date - 14 ORDER BY date;
```

Everything else about traffic (sources, pages, geography, devices, engagement rate) comes
from **GA4**, which is now the source of truth — this app no longer stores it.

### 5.3 GA4 (pull by hand)

In the GA4 property, Reports → set the date range to **last 28 days**, and record:
sessions, active users, new users, engagement rate, average engagement time, top 5
countries, top 5 pages/screens, and acquisition by channel (Direct / Organic Search /
Organic Social / Referral). The leading indicator worth watching is **Search Console
impressions** on the `/foods` SEO pages (shipped ~2026-10-16) — the first sign organic is starting.

> **⚠️ Always separate bot/crawler noise from the real audience.** GA4 drops only
> *known* bots; crawler traffic that evades that filter is the **bulk** of this tiny
> app's sessions (at the 2026-10-19 snapshot, only **16 of 80** sessions were real).
> Do **not** filter by country — that wrongly discards legitimate users abroad. Instead
> flag two reliable tells, which `mix report.snapshot` applies automatically
> (`Mehungry.Report.GA4`):
>
> 1. **Datacenter-city denylist.** Sessions geolocating to hyperscaler datacenter towns
>    are near-certain hosting/crawler traffic. Most of this app's noise is **Meta/Facebook
>    link-preview crawlers** (we auto-post recipe URLs to Facebook), which resolve to Meta
>    datacenter towns — **Prineville, Forest City, Luleå (= the "Sweden" traffic), Altoona,
>    Gallatin** — plus AWS/Google towns (Boardman, The Dalles, Ashburn…). The report prints
>    a `cities:` breakdown precisely so you can **curate the denylist from evidence**: add a
>    city once you've confirmed it's a datacenter town and never a real market. The list is
>    `@default_datacenter_cities` in `ga4.ex`; override with
>    `config :mehungry, :ga4_datacenter_cities, [...]` (values must match GA4's `city`
>    labels exactly — note GA4 writes "Lulea"/"Rethimno" without diacritics). **Keep
>    ambiguous real cities out** (Dublin, Springfield, Fort Worth host datacenters but are
>    also real places).
> 2. **Non-engaged / <10s sessions.** GA4's `engagedSessions` = sessions that lasted >10s,
>    had 2+ views, or converted; `sessions − engagedSessions` is the sub-10-second,
>    single-view, bot-like bucket.
>
> **The headline number is `REAL audience` = engaged (>10s) AND not from a datacenter city**
> (datacenter *engaged* sessions are subtracted so the two filters don't double-count),
> with the raw incl.-bots total shown alongside — **never the raw number alone.** Both are
> proxies, so treat large swings as "verify", confirming against GA4's own bot reporting.

### 5.4 Derived metrics (how the ratios in §1–3 are computed)

- **Confirmation rate** = `users_confirmed / users_total` = 16 / 49 = **33%**
- **Onboarding completion** = `profiles_onboarded / users_total` = 15 / 49 = **31%**
- **Authoring rate** = `recipe_authors / users_total` = 5 / 49 = **~10%**
- **Posts-per-recipe** = `posts_total / recipes_total` = 483 / 85 = **~5.7** (inflation from translations + bot posts — do **not** read posts as user activity)
- **Engagement actions** = comments + likes + saves + follows = 1 + 0 + 25 + 8 = **34 total, ever**

---

## 6. Snapshot log

> 🔁 **Before the next snapshot, check whether the analytics-removal branch has deployed.**
> If it has, the `visits` table no longer exists — use the **§5.2 post-deploy** queries
> (`daily_session_metrics` + GA4) for the traffic column, **not** the §5.1 `visits` queries.
> The users/recipes/engagement queries in §5.1 are unchanged either way.

Append one row per weekly check (run §5.1 pre-deploy, §5.2 post-deploy). Keep it terse — trends matter more than absolute precision.

| Date | Users (confirmed) | New users /30d | Recipes (authors) | Comments / Likes / Saves / Follows | Traffic (source) | Notes |
|---|---|---|---|---|---|---|
| 2026-10-17 | 49 (16) | 4 | 85 (5) | 1 / 0 / 25 / 8 | ~150 GA4 sessions/mo; 98.3% Greece; 0 organic | Baseline. July-2026 signup spike (27) never retained. `visits`=4,203 all-time, 114 distinct IPs, tracking since 2026-05-19; 411 visits/30d. Social dormant: FB 0 followers/0 eng; Pinterest 73 impr / 3 outbound clicks / audience 1 (30d). |
| 2026-10-19 | 49 (16) | 4 | 67 (5) | 1 / 0 / 19 / 8 | **~16 real GA4 sessions/28d** (80 raw: 50 datacenter-city + 58 <10s non-engaged); 828 GSC impr (/foods: 460); 25 anon sessions all-time | **First automated `mix report.snapshot`** (DB+GA4+GSC). **Organic search has started** (vs "0 organic" baseline): 828 GSC impressions / 13 clicks, 460 impr on `/foods`, avg pos 12.6 — top queries are USDA nutrient lookups. **GA4 bot-filtering added this day** (see §5.3): of 80 raw sessions only **~16 are real** (engaged >10s + non-datacenter). The inflated "US=46 > GR=19 / Sweden=11" geo is **Meta/Facebook link-preview crawlers** resolving to Meta datacenter towns (Prineville 18, Forest City 11, Luleå 11 = the "Sweden", Altoona, Gallatin) — a consequence of auto-posting recipe URLs to FB, not a real audience shift. Genuine core is still Crete (Rethimno 14, Ierapetra 5, Heraklion 1). Recipes **85→67** (deletions via the new delete/clear-week features — confirm intended). Social: FB M3hungry 1 follower (insights n/a). **Pinterest fixed this day**: root cause was `PINTEREST_ENV` unset → OAuth exchanged against the Pinterest **sandbox**, whose tokens lack a durable refresh token (`:no_refresh_token`). Set `PINTEREST_ENV=live` (Fly secret + `fly.toml [env]`), reconnected from `/profile`, and the snapshot now pulls live analytics: 76 impr / 9 pin clicks / 3 outbound / 12 engagements. |

**What to watch week-over-week**
1. **New users /30d** — is the trickle turning into a trend, or still flat at ~4?
2. **Organic search** — any GA4 organic sessions / Search Console impressions on `/foods`? (currently zero — this is the #1 unlock)
3. **Engagement actions** — do comments/likes/saves move off the floor, or is content still write-only?
4. **Confirmation rate** — if it stays ~33%, the signup→confirm step is leaking and worth fixing.
5. **Anonymous sessions** (post-deploy) — the consent-independent denominator vs. GA4's consented ~150/mo tells you how much the cookie banner is hiding.

---

## 7. Automating this report

**✅ Implemented as `mix report.snapshot`** (see §7.0). The task pulls all four sources —
DB (§7.1), GA4 (§7.2), Facebook (§7.3), Pinterest (§7.4) — in one pass and prints a
human-readable report ending with a ready-to-paste §6 log row. Every external source
**degrades gracefully**: when its credential / scope / env var is missing, that section shows a
clear "not configured" note and the rest still renders, so the DB figures always print and you
paste the missing one by hand. The §7.1–7.4 subsections below are now the **one-time setup** to
switch each source from "paste by hand" to "pulled automatically".

The agent is still deliberately **blocked from reading production** without explicit
authorization, so in practice you (or an operator with prod env) run the task and hand the
output back for interpretation. Note that the **social sources (§7.3–7.4) are cheaper than GA4
(§7.2)**: the app already stores OAuth tokens and ships HTTP clients for them, so there's no new
credential to provision — Facebook needed only one extra scope (`read_insights`, already added).

### 7.0 The `mix report.snapshot` command

```bash
mix report.snapshot            # full report, last 28-day window for GA4/Pinterest
mix report.snapshot --days 7   # narrower GA4/Pinterest window
mix report.snapshot --row      # print ONLY the §6 markdown log row
```

Code: `Mehungry.Report.Snapshot` (orchestrator + formatting), `Mehungry.Report.GoogleAuth`
(shared service-account auth), `Mehungry.Report.GA4` (Data API client),
`Mehungry.Report.SearchConsole` (organic-search client),
`Mehungry.Social.Facebook.page_insights/1`, `Mehungry.Social.Pinterest.user_account_analytics/3`,
`Mehungry.Meta.session_metrics_summary/0`. Optional env vars that light up each source:

| Env var | Turns on | Section |
|---|---|---|
| `REPORT_RO_DATABASE_URL` | reads the DB through the read-only role instead of the app Repo | §7.1 |
| `GA4_SA_KEY` + `GA4_PROPERTY_ID` | the GA4 pull | §7.2 |
| `GA4_SA_KEY` + `GSC_SITE_URL` | the Search Console pull (same service account as GA4) | §7.2 |
| *(none — token already stored)* | Facebook Page insights (reconnect Page once for the new scope) | §7.3 |
| `PINTEREST_ENV=live` | real Pinterest analytics (sandbox returns nothing) | §7.4 |

### 7.1 Auto DB pull — read-only Postgres role (recommended)

Create a SELECT-only role in Supabase so any automated access can **only read** (blast radius =
reads, even if misused):

```sql
-- run once in the Supabase SQL editor
CREATE ROLE report_ro LOGIN PASSWORD '<strong-random-password>';
GRANT CONNECT ON DATABASE postgres TO report_ro;
GRANT USAGE ON SCHEMA public TO report_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO report_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO report_ro;
```

Then store its connection string (Supabase → Project Settings → Database → use the **pooler**
host) as `REPORT_RO_DATABASE_URL`. **`mix report.snapshot` reads through it automatically** when
set (the reporting aggregate is routed via a transient read-only Postgrex connection); when
unset, the task falls back to the app `Repo`. Include `?sslmode=require` in the URL for the
managed pooler. (The role is also what you'd grant if you ever let the agent run the §5 SQL via
`psql` directly — no write access, no production shell.)

**Alternative (faster, broader, *not* recommended):** add a Claude Code Bash allow-rule for
the read-only release eval (e.g. `Bash(fly ssh console:*)` in `.claude/settings.json`). This
avoids creating a DB role, but it grants the agent a **full production shell**, so the
contained read-only role above is the safer choice.

### 7.2 Auto GA4 + Search Console pull — one Google service account, two APIs

GA4 and Search Console are both unreadable today (no credential). **The same service account
unlocks both** (`Mehungry.Report.GoogleAuth` mints a per-scope token; `GA4_SA_KEY` holds the
one JSON key). To automate them:

1. In Google Cloud, create a **service account** and enable **both** the **Google Analytics
   Data API** and the **Search Console API** on the project.
2. Grant the service-account email read access **in each product separately**:
   - GA4 → Admin → Property Access Management → add as **Viewer**.
   - Search Console → Settings → Users and permissions → add (at least **Restricted**).
3. Download the service-account **JSON key**; store it as `GA4_SA_KEY` (the raw JSON inline or a
   path to the `.json` file). Then set:
   - `GA4_PROPERTY_ID` — the **numeric** GA4 property id (Admin → Property Settings; *not* the
     `G-XXXX` measurement id).
   - `GSC_SITE_URL` — the exact Search Console property id: a **domain** property is
     `sc-domain:m3hungry.com`; a **URL-prefix** property is `https://www.m3hungry.com/`.
4. `Mehungry.Report.GA4.fetch/1` calls the Data API `runReport` for sessions, active/new users,
   engagement rate, channels, countries and top pages; `Mehungry.Report.SearchConsole.fetch/1`
   calls `searchAnalytics.query` for clicks/impressions/CTR/position overall, the **`/foods`
   subset** (the organic leading indicator this report watches most), plus top queries and
   pages. **(Already coded** — the JWT is signed with Erlang's `:public_key`, no JWT dependency;
   `mix report.snapshot` skips each source until its env vars are set, and GA4 and Search Console
   switch on independently — you can enable one without the other.)

   Note Search Console data lags ~2-3 days, so the newest day(s) in the window may read as empty.

### 7.3 Auto Facebook Page insights — Graph API (token already exists)

The app already connects a Facebook Page and stores its **Page access token** in
`user.facebook_token` (a list of pages, each with an `access_token`), used by
`Mehungry.Social.Facebook` to publish. Reach/engagement is one more call against the same
base (`https://graph.facebook.com/`):

```
GET /{PAGE_ID}?fields=followers_count,fan_count
GET /{PAGE_ID}/insights?metric=page_impressions_unique,page_post_engagements,page_views_total&period=days_28
```

- **(Already coded** — `Mehungry.Social.Facebook.page_insights/1`, called by `mix report.snapshot`.)
- **Scope — done, one action left:** `read_insights` has been **added** to `default_scope` (see
  `Ueberauth.Strategy.Local.Facebook`). The one remaining manual step is to **re-connect the Page
  once** so the stored token carries the new scope; until then follower counts return but the
  insight metrics come back as an `error` on the per-page line (the report says so explicitly).
- **Caveat:** Meta regularly deprecates organic Page-Insights metrics between Graph API
  versions — verify the metric names against the current version before relying on them.
- Gives: Page followers, 28-day reach/impressions, post engagements — the off-site social
  reach GA4 can't see (GA4 only counts visitors who land **on** the site).

### 7.4 Auto Pinterest analytics — API v5 (token already exists, scope already present)

The app stores a Pinterest OAuth token in `user.pinterest_token`, auto-refreshed daily by
`PinterestTokenRefreshWorker`, and talks to API v5 via `Mehungry.Social.Pinterest`. The
connect scope already includes `user_accounts:read` + `pins:read`
(`MehungryWeb.Ueberauth.Strategy.Pinterest`), which is what analytics needs — so this is the
lowest-effort of all: just add the call.

```
GET /v5/user_account/analytics?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD
    &metric_types=IMPRESSION,SAVE,PIN_CLICK,OUTBOUND_CLICK,ENGAGEMENT
```

- **(Already coded** — `Mehungry.Social.Pinterest.user_account_analytics/3`, reusing
  `authed_request/2` for token refresh and the env-aware `api_base/0`; called by `mix report.snapshot`.)
- **Must be live, not sandbox:** set `PINTEREST_ENV=live` (otherwise `api_base` points at the
  sandbox and returns no real data). The function short-circuits with a clear "sandbox" note
  until you do.
- Gives: impressions, saves, pin clicks, outbound clicks (= referral traffic Pinterest sends
  you) and total engagements.

### 7.5 Scheduling

With the gathering wired into `mix report.snapshot` (§7.0), the only thing left to make this
hands-off is a schedule. Run the task weekly from an environment that has prod access (its env
vars), capture the `--row` output, and append it to the §6 log — e.g. a Fly scheduled machine,
a cron, or a Claude Code routine that runs `mix report.snapshot --row` and commits the new row.
Because every source degrades gracefully, the schedule produces a useful row from day one and
fills in GA4 / Facebook / Pinterest columns automatically as each source's setup (§7.1–7.4) is
completed.
