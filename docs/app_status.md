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
| _next week_ | | | | | | |

**What to watch week-over-week**
1. **New users /30d** — is the trickle turning into a trend, or still flat at ~4?
2. **Organic search** — any GA4 organic sessions / Search Console impressions on `/foods`? (currently zero — this is the #1 unlock)
3. **Engagement actions** — do comments/likes/saves move off the floor, or is content still write-only?
4. **Confirmation rate** — if it stays ~33%, the signup→confirm step is leaking and worth fixing.
5. **Anonymous sessions** (post-deploy) — the consent-independent denominator vs. GA4's consented ~150/mo tells you how much the cookie banner is hiding.

---

## 7. Automating this report (possible upgrade — not yet done)

Today this snapshot is **manual**: a human runs the §5 SQL in the Supabase editor and pulls
GA4 / social figures by hand, then pastes them in. The agent is deliberately **blocked from
reading production** without explicit authorization. A few optional upgrades would make it
hands-off; each is a one-time setup. Note that the **social sources (§7.3–7.4) are cheaper than
GA4 (§7.2)**: the app already stores OAuth tokens and ships HTTP clients for them, so there's no
new credential to provision — mostly just adding read calls (and, for Facebook, one extra scope).

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
host) as a secret the agent can read, e.g. `REPORT_RO_DATABASE_URL`, and allow `psql`. The
agent runs the §5.1/§5.2 queries directly — no write access, no production shell.

**Alternative (faster, broader, *not* recommended):** add a Claude Code Bash allow-rule for
the read-only release eval (e.g. `Bash(fly ssh console:*)` in `.claude/settings.json`). This
avoids creating a DB role, but it grants the agent a **full production shell**, so the
contained read-only role above is the safer choice.

### 7.2 Auto GA4 pull — Google service account + Analytics Data API

GA4 is unreadable today (no credential). To automate it:

1. In Google Cloud, create a **service account** and enable the **Google Analytics Data API**.
2. In GA4 → Admin → Property Access Management, add the service-account email as a **Viewer**.
3. Download the service-account **JSON key**; store it as a secret (`GA4_SA_KEY`) and set
   `GA4_PROPERTY_ID`.
4. A small script then calls the Data API `runReport` for sessions, active/new users,
   engagement rate, channels, countries, and top pages — the §5.3 figures, fetched automatically.

### 7.3 Auto Facebook Page insights — Graph API (token already exists)

The app already connects a Facebook Page and stores its **Page access token** in
`user.facebook_token` (a list of pages, each with an `access_token`), used by
`Mehungry.Social.Facebook` to publish. Reach/engagement is one more call against the same
base (`https://graph.facebook.com/`):

```
GET /{PAGE_ID}?fields=followers_count,fan_count
GET /{PAGE_ID}/insights?metric=page_impressions_unique,page_post_engagements,page_views_total&period=days_28
```

- **Scope gap:** the current OAuth scope is `pages_read_engagement, pages_manage_posts,
  pages_manage_engagement` (see `MehungryWeb.Ueberauth.Strategy.Facebook`). Page **Insights**
  additionally needs **`read_insights`** — add it to `default_scope` and re-connect the Page
  once to mint a token that carries it.
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

- Reuse `authed_request/2` in `Mehungry.Social.Pinterest` (handles token refresh) and the
  `api_base/0` base URL.
- **Must be live, not sandbox:** set `PINTEREST_ENV=live` (otherwise `api_base` points at the
  sandbox and returns no real data).
- Gives: impressions, saves, pin clicks, outbound clicks (= referral traffic Pinterest sends
  you) and total engagements.

### 7.5 Scheduling

Once any of these sources are wired up, the weekly snapshot can run on a schedule (e.g. a
cron/routine) that executes the §5 queries + the §7.2–7.4 API calls and appends a new row to
the §6 log — turning this from a manual chore into an automatic weekly diff. Until then, keep
doing the manual paste.
