# Wearable / Health-Data Integration — Feasibility & Decision Record

> **Status: EVALUATION ONLY — not built, not scheduled.** This is a decision record to
> revisit. Nothing in the codebase implements any of this yet.
> **Date:** 2026-11-18. **Revisit trigger:** see [§7](#7-when-to-revisit).

The original question was "integrate m3hungry with Fitbit." The short answer is that
**the Fitbit Web API no longer exists**, so the real question is whether to integrate with
its successors — the **Google Health API** (cloud) and/or **Apple HealthKit** + Android
**Health Connect** (on-device). This doc captures the value, the business case, the
complexity (grounded in existing repo patterns), and the recommendation.

---

## 1. Critical finding: the Fitbit Web API is gone

- The **legacy Fitbit Web API was permanently shut off on 2026-11-02** (~2 weeks before this
  doc). Legacy OAuth endpoints no longer sync data.
- **New Fitbit developer app registrations had already closed** before that.
- Fitbit data now lives behind the **Google Health API** (cloud, Google OAuth 2.0) and
  **Health Connect** (on-device Android). Existing Fitbit OAuth tokens do **not** carry over —
  every user must re-consent through Google.
- The Google Health API is a different architecture: ~44 data types via uniform read methods
  (`list` / `reconcile` / `rollUp` / `dailyRollUp`) + webhooks, not the old 120+ REST endpoints.
  Weight, body-fat, sleep, heart-rate, and activity/exercise are all supported; ~11 types are
  writable.

**Implication:** "Fitbit integration" is dead as framed. Any integration today is a
**Google Health** integration (with Fitbit as one upstream source), or an **Apple HealthKit /
Health Connect** integration living in the native mobile app. Design for the source being
swappable, not Fitbit-specific.

Sources (captured 2026-11-18):
- <https://www.themomentum.ai/blog/fitbit-web-api-deprecation-google-health-migration>
- <https://openwearables.io/blog/fitbit-web-api-shutdown-2026-migration-guide>
- <https://sahha.ai/blog/fitbit-api-sunset-migration/>
- <https://developers.google.com/health/get-started>
- <https://developers.google.com/health/data-types>
- <https://aifitnessapi.com/google-health-api>

---

## 2. What value it adds to users

Wearable data — **weight, body-fat %, activity/steps, calories burned, resting HR, sleep** —
maps cleanly onto things m3hungry already models by hand.

### For the diet-watcher (consumer side)
- **Kills manual entry in the Progress journal.** Today weight / body-fat / waist in
  `/profile?tab=progress` are typed by hand (`progress_entries`). Auto-sync fills the progress
  chart itself — the biggest friction-killer, and it keeps the app warm between visits.
- **Energy balance — the one genuinely new feature.** We already compute *calories consumed*
  from the calendar (`History.daily_nutrition_history/3`). A wearable gives *calories burned*.
  Together = an honest daily energy balance, which we **cannot** produce today. This is the
  standout win and is especially relevant to the secondary fitness audience.

### For the nutritionist (the north-star relationship)
- **Objective between-visit data on the client file.** `ConsultationNote` measurements and
  `measurement_history_for_user/1` currently depend on client self-report at appointments.
  Wearable sync gives adherence, activity, sleep, and weight-trend data without relying on the
  client's memory/honesty — directly deepening the diet-watcher ↔ nutritionist loop that the
  product foundation says every change must serve.

**Verdict on product fit: strongly on-mission.** It feeds Progress, unlocks energy balance,
and enriches the client file. No "why would we build this" problem conceptually.

---

## 3. What we gain (business case)

**Upside**
- **Retention/engagement:** passive daily data flow is sticky; a reason to open the app daily.
- **Competitive wedge:** vs. Athlisis-style static condition handouts, "your client's live
  objective weight/activity/sleep trend on their file" is something a handout vendor can't match.

**Honest counterweights**
- **Reachable audience is ~nil today.** ~98% Greece, ~150 sessions/mo. Fitbit penetration in
  Greece is low (Garmin/Xiaomi/Apple/Samsung dominate), and Fitbit-the-brand is being absorbed
  into Google. Users who own a Fitbit *and* use our app ≈ zero right now. ROI today is about
  *future* capability, not present users.
- **GDPR weight:** wearable health data is Art. 9 special-category data. We have the
  private-bucket pattern (progress photos), but there is a known erasure-cascade gap; a
  continuous health feed raises the stakes on consent + deletion correctness.
- **Platform risk:** Google has a track record of sunsetting health APIs (Fitbit Web API,
  Google Fit). Betting on one cloud API is fragile; a swappable-source design hedges this.

---

## 4. Complexity — grounded in existing repo patterns

**Internal Elixir effort is small** because the exact integration shape already exists and can
be cloned. **The blockers are external** (API access/approval + GDPR), not code.

### 4.1 The template to clone: Google Calendar two-way sync
This is the closest analog — a connect flow *separate from login*, an **offline refresh token**
in a dedicated table, a cron-driven import worker, and a mockable HTTP client behind a config
seam. Reusable pieces:

| Piece | File | Role |
|---|---|---|
| Token table | `apps/mehungry/lib/mehungry/professionals/google_account.ex` (`professional_google_accounts`) | `access_token`/`refresh_token`/`token_expires_at`/`scope`; `access_token_expired?/2`, `token_attrs/2` |
| Orchestration + HTTP client | `apps/mehungry/lib/mehungry/professionals/google_calendar.ex` | `ensure_fresh_token/1` (refresh-on-read), `import_busy/2` (poll→parse→write); client behind `:google_calendar_client` config seam (stubbed in tests) |
| Connect flow (not login) | `controllers/google_calendar_oauth_controller.ex` + branch in `controllers/auth_controller.ex` + routes `router.ex:446-447` | sets session marker, redirects to `/auth/google` with `access_type=offline&prompt=consent` to force a refresh token |
| Import worker | `oban_workers/google_calendar_busy_import_worker.ex` | cron sweep of all accounts + targeted enqueue after connect |
| Cron entry | `config/config.exs:239` (`*/20 * * * *`) | periodic import |

**A health integration = clone this feature, swap the client** behind a new
`:health_source_client` (or `:google_health_client`) config seam, exactly like
`:google_calendar_client`.

### 4.2 Token refresh patterns
Two idioms exist; either works:
- **Refresh-on-read** — `ensure_fresh_token/1` in `google_calendar.ex` (preferred; simplest).
- **Dedicated cron refresh worker** — `oban_workers/instagram_token_refresh_worker.ex`,
  `pinterest_token_refresh_worker.ex` (`config.exs:227`, `:229`). These store tokens as a jsonb
  map on `accounts/user.ex` (`:instagram_token`, `:pinterest_token`) with helpers in
  `social/instagram/token.ex` / `social/pinterest/token.ex`. For health data prefer the Google
  **dedicated-table** idiom since we store imported data anyway.

### 4.3 OAuth / Ueberauth
- Providers configured in `config/config.exs:338-386`, secrets wired in
  `config/runtime.exs:233-247`. Fitbit/Google-Health adds one provider entry + one env pair.
- We already **hand-roll custom Ueberauth strategies** (`apps/mehungry_web/lib/mehungry_web/
  ueberauth/strategy/{instagram,pinterest}.ex` + `oath.ex`), so no library is required.
- Connect-not-login pattern: `controllers/social_oauth_controller.ex` sets a session
  `oauth_intent` and reuses the shared `/auth/:provider` callback; the Google Calendar variant
  (offline token + dedicated table) is the closest fit.

### 4.4 Write targets already exist (render for free)
- **Body metrics** (weight / body-fat / waist / muscle-mass) → `progress_entries` via
  `Progress.upsert_entry_by_date/4` (`apps/mehungry/lib/mehungry/progress/entry.ex`,
  `progress.ex:273`). The chart (`measurement_chart.ex`) keys on a `source:` field
  (`:self`/`:intake`/`:visit` today) — a `:fitbit`/`:health` source slots in with **zero new
  rendering code**. Same for the nutritionist client file via
  `Professionals.measurement_history_for_user/1` (`professionals.ex:2534`).
- **Calories consumed** (to pair against "burned") → `History.daily_nutrition_history/3`
  (`history.ex:223`). An existing overlay chart (`progress_overlay_chart.ex`) is the natural
  home for a burned-calories overlay.

### 4.5 The genuinely new work (no existing home)
1. Token table + health HTTP client + Ueberauth strategy + connect controller/routes/config —
   all pattern-clones. **~1 week.**
2. **One new schema** — `progress_entries` only covers weight/body-fat/waist/muscle.
   **Activity, steps, sleep, and resting HR have no column home**, so they need a new
   daily-metrics table + migration.
3. The energy-balance view (pairing the two daily series).

**Internal estimate: ~1–2 weeks of Elixir.** The expensive parts are external:
Google's **sensitive-health-scope verification/security review**, and the **GDPR Art. 9**
consent/storage/erasure surface.

### 4.6 Path comparison
| Path | What it takes | Verdict |
|---|---|---|
| **Google Health API (cloud)** — Fitbit successor | Google Cloud project, OAuth consent screen + Google's restricted-health-scope verification, map onto v4 model (44 types, `rollUp`/`dailyRollUp` + webhooks). Reuses the Calendar-sync pattern ~1:1. | **Medium.** Eng is small; Google's app-verification is the timeline risk. |
| **Health Connect (on-device Android)** | Lives in the **React Native mobile app**, not web. Reads an on-device aggregation of Fitbit/Garmin/Samsung/etc. Broad device coverage, no cloud-OAuth review. | **Medium, different surface.** Best coverage, but mobile-codebase work. |
| **Apple HealthKit (on-device iOS)** | Mobile app, iOS only. Reads Apple Watch + iPhone health data. | **Medium, mobile.** Pairs with Health Connect for full mobile coverage. |

---

## 5. Recommendation

1. **Do not build a Fitbit-specific integration.** That window closed on 2026-11-02.
2. **Not a near-term priority.** With ~0 reachable wearable users today, near-term ROI is low.
3. **Ship the no-regrets piece now: the energy-balance feature** — it reuses
   `History.daily_nutrition_history/3` + a manual/estimated "calories burned" input and delivers
   ~80% of the user-facing value with **zero external-API risk**. A wearable later just
   auto-fills that same field.
4. **When wearable sync is justified, build it generically.** Clone the Google Calendar feature
   behind a **`health_source` adapter seam** (mirroring `:google_calendar_client`), so
   Google Health API / Apple HealthKit / Health Connect are interchangeable adapters rather than
   a Fitbit-specific dead end.
5. **Highest-coverage path is on-device (Health Connect + HealthKit) in the mobile app**, not the
   Google Health cloud API — *if* users live in the mobile client.

---

## 6. Rough implementation sketch (for when we revisit)

- **New `health_source` seam** — config key `:health_source_client` behind a behaviour, stubbed
  in tests (copy `:google_calendar_client`). Adapters: `GoogleHealth`, later `HealthKit` /
  `HealthConnect` (mobile-bridged).
- **Clone the Google Calendar feature**: `health_account` token table + orchestration module
  (`ensure_fresh_token/1` + `import_metrics/2`) + connect controller + callback branch + routes
  + cron import worker + cron entry.
- **Reuse write targets**: body metrics → `Progress.upsert_entry_by_date/4` with a new `source:
  :health`; charts render unchanged.
- **New schema** for activity/steps/sleep/resting-HR daily series (no existing column home).
- **Energy balance**: daily "burned" series keyed by date, paired with
  `History.daily_nutrition_history/3`; surface on `progress_overlay_chart.ex`.
- **GDPR**: explicit consent at connect, store under the existing private-bucket/sensitive-data
  discipline, ensure the erasure cascade covers the new tables.
- **Docs to update on build**: this file → an implementation doc; `mobile_api_spec.md` if any
  `/api/v1` surface is added; `docs/implementation/entities/` if a new entity schema lands.

---

## 7. When to revisit

Revisit when **any** of these becomes true:
- A meaningful share of active users own wearables (Apple Watch / Garmin / Samsung / Fitbit) —
  watch for user requests or a non-Greek/fitness-leaning audience shift.
- We go mobile-first enough that Health Connect / HealthKit coverage is worth the native work.
- A nutritionist explicitly asks for objective between-visit client data as a paid differentiator.
- The energy-balance feature (step 3) ships and users ask to automate the "calories burned" input.

Until then: **park the wearable sync; build energy-balance manually first.**
