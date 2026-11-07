# Progress Journal — mobile implementation guide (spec §19)

> The hand-off document for building the self-tracking **Progress Journal** in the
> React Native client. The API contract lives in `mobile_api_spec.md` **§19**
> (plus §11 for photo upload); this guide explains the concepts, the state
> machine, the flows, and the screen composition the web client ships, so the
> app can mirror it. Server feature doc: `docs/features/progress_journal.md`.

## 1. The concept in one paragraph

A user — **with or without a nutritionist** — tracks their own body progress in
a journal organised into **periods**. A period is a date range (`started_on` →
`ended_on`, open-ended while active); the user has **exactly one active period**
at all times (server-enforced, never create one client-side — the list endpoint
bootstraps it). In a **self** period the user picks which metrics to track,
sets goals, logs dated diary entries (measurements + note + photos), and can
"start over from 0" (reset). When they start working with a nutritionist, the
server **automatically** closes their period and opens a **nutritionist-aligned**
one: self-logging pauses, and that period's chart is fed by the nutritionist's
recorded measurements instead. Past periods are never deleted — they are the
"Progress history", each openable read-only. A period can be **shared** with
the assigned nutritionist (opt-in, revocable).

## 2. Data model (what the API returns)

### Period
```json
{ "id": 12,
  "kind": "self",                      // "self" | "nutritionist_aligned"
  "professional_id": null,             // set on aligned periods
  "started_on": "2026-10-22",
  "ended_on": null,                    // null = active/ongoing
  "active": true,                      // convenience: ended_on == null
  "self_logging": true,                // kind == "self" && active → show editors
  "tracked_metrics": ["weight_kg", "waist_cm"],
  "goals": { "weight_kg": 72.0 },      // metric → target (user-set)
  "shared_with_nutritionist": false,
  "title": null, "notes": null,        // optional user labels
  "height_m": 1.75, "sex": "male", "age": 34 }  // anthropometric snapshot
```

- **Selectable metrics** (what a user may track): `weight_kg`, `waist_cm`,
  `body_fat_percentage`, `muscle_mass_kg`.
- **Derived metrics** (never input): `bmi` (needs `height_m`), `bmr_kcal`
  (needs `sex` + `age` + `height_m`). Computed server-side on every entry write
  from the period's snapshot — if the snapshot is missing they stay `null`
  (the server never fabricates).
- `self_logging` is the single flag that decides whether to render the log
  form / goals editor / reset button. **Gate all editing UI on it.**

### Entry (diary row)
```json
{ "id": 51, "period_id": 12, "entry_date": "2026-10-22",
  "weight_kg": 80.0, "waist_cm": 92.0, "body_fat_percentage": null,
  "muscle_mass_kg": null, "bmi": 26.1, "bmr_kcal": 1731,
  "note": "Day one. Felt good.",
  "photos": [ { "id": 7, "url": "https://…", "caption": null, "position": 0 } ] }
```
**One entry per date per period** — logging the same date again *updates* that
entry (true upsert; same `id` comes back). Design the "log" screen as
"today's entry" rather than "new entry".

### History point (chart data)
```json
{ "date": "2026-10-22", "source": "self",
  "weight_kg": 80.0, "body_fat_percentage": null, "waist_cm": 92.0,
  "muscle_mass_kg": null, "bmi": 26.1, "bmr_kcal": 1731 }
```
`source` ∈ `self | intake | visit`. Self periods only emit `self`; aligned
periods emit `intake`/`visit` (nutritionist-recorded). Same shape as §18's
`GET /me/progress` points — reuse your §18 chart component if you built one.

## 3. The period state machine

```
                      ┌──────────────────────────┐
   (first API call)   │  SELF (active)           │  log entries, goals, photos,
  ───bootstrap──────▶ │  self_logging: true      │  reset, share
                      └──────┬───────────┬───────┘
         POST /reset ────────┘           │ user accepts a nutritionist invite
   (close + reopen self)                 ▼ (server-side, automatic)
                      ┌──────────────────────────┐
                      │  NUTRITIONIST_ALIGNED    │  read-only for the user;
                      │  (active)                │  chart fed by nutritionist
                      │  self_logging: false     │  measurements; share still works
                      └──────┬───────────────────┘
                             │ assignment removed (either side)
                             ▼ (server-side, automatic)
                      fresh SELF period (active); the aligned one → history
```

Key client consequences:
- **Never create or close periods except via `POST /reset`.** The alignment
  transitions happen server-side when invitations are accepted / assignments
  removed — after any "accept invitation" or "disconnect nutritionist" action
  (§18 endpoints), **refetch `GET /me/progress/periods`**.
- When the active period is aligned, show the notice: *"Your nutritionist now
  tracks your progress — measurements from your visits chart here
  automatically, and self-logging is paused. Your earlier self-logged progress
  is saved below under past periods."*
- Aligned history has **no lower date bound**: nutritionist measurements that
  predate the assignment still chart (matches §18's flat view). A *closed*
  aligned period excludes measurements recorded after its `ended_on`.
- A nutritionist **switch** (accepting a new invite while assigned) closes the
  old aligned period and opens a new one — no special client handling, just
  refetch.

## 4. Endpoints (all 🔒 bearer; full JSON in spec §19)

| Call | Use |
|---|---|
| `GET /me/progress/periods` | Journal home. **Bootstraps on first call** (creates the right first period). Returns `active_period_id` + all periods, newest first. |
| `GET /me/progress/periods/:id` | One period's dashboard payload: period + `metrics` (localized labels/units) + `context` (incl. `goals`) + `history` + `comparison` + `photo_markers`. |
| `POST /me/progress/periods` | Idempotent bootstrap; optional `{"period": {…}}` applies configuration in the same call. Handy as the single "ensure + configure" call on onboarding. |
| `PATCH /me/progress/periods/:id` | Configure a self period: `goals`, `tracked_metrics`, `title`, `notes`, `height_m`, `sex`, `age`. 422 on aligned periods. |
| `POST /me/progress/reset` | "Start over from 0" → `{closed, opened}`. Confirm with the user first (copy: progress stays saved as a past period). |
| `POST /me/progress/periods/:id/share` / `DELETE …/share` | Opt the period in/out of nutritionist visibility. POST → 422 `no nutritionist` when unassigned (show "You don't have a nutritionist to share with yet"). |
| `GET /me/progress/periods/:id/entries` | Diary entries, oldest first, photos embedded. Render newest-first. |
| `POST /me/progress/entries` | `{"period_id": …, "entry": {…}}` — upsert by `entry_date` (defaults to today). Don't send `bmi`/`bmr_kcal` (ignored). 422 `not self period` on aligned. |
| `DELETE /me/progress/entries/:id` | 204; removes its photos too (rows + storage). |
| `POST /me/progress/photos` | `{"entry_id": …, "upload_id": …}` after the §11 presign flow. Never send a URL. |
| `DELETE /me/progress/photos/:id` | 204; removes the storage object too. |

Errors follow the §1 envelope: 404 for any id that isn't yours (treat as "gone"),
422 with `{"errors": {"detail": …, "fields": …}}` for validation, 401 unauth.

## 5. Photo upload flow (3 steps)

1. `POST /api/v1/uploads/presign` with `{"kind": "progress_photo", "content_type": "image/jpeg"}`
   → `{upload_id, url, method, headers}`.
2. HTTP `PUT` the binary to `url` with the returned `headers`.
3. `POST /api/v1/me/progress/photos` with `{entry_id, upload_id}` → the photo
   object with its public `url`.

So a photo always belongs to a diary entry (that's what pins it to a date).
The natural UX: attach photos while logging today's entry — upsert the entry
first, then attach each photo to the returned `entry.id`. Max 4 per entry,
JPG/PNG/WebP, ≤ 5 MB (server-enforced limits on the web client; mirror them).

## 6. Screen composition (what the web ships — mirror the hierarchy)

**Journal home** (`GET /periods` + `GET /periods/:active_id`):
1. *Aligned notice banner* — only when the active period is aligned.
2. *Period header* — title (or "My progress"), date range ("Oct 22, 2026 –
   ongoing"), kind badge (`self-tracked` / `with nutritionist`), **share
   toggle**, **Start over** button (self only), goal chips ("Goal: Weight 72 kg").
3. *Before → Now* — two photo cards (`comparison.before/.now`) with their dates
   and per-metric deltas between the two compared entries (compute client-side
   from `comparison.*.entry`; color by direction — down is good for
   weight/waist/body-fat/BMI, up is good for muscle mass, BMR neutral).
   Render only when `comparison != null`.
4. *Metric dashboard* — one KPI card per metric with ≥ 2 points in `history`
   (current value, delta since first point, sparkline); tapping a card selects
   the trend chart's metric. Draw a dashed **goal line** when
   `context.goals[metric]` exists. Legend by `source` ("logged by you" for
   self; "intake"/"visit" for aligned).
5. *Photo strip* — `photo_markers` thumbnails pinned under the chart's date
   axis at `(date - min) / (max - min)` of the plotted width (use the selected
   metric's point range). Tap → fullscreen viewer.
6. *Diary* — the "log today" form **iff `self_logging`** (date ≤ today,
   numeric field per `tracked_metrics`, note, photo picker), then entries
   newest-first (date, measurements incl. derived BMI/BMR, note, photo
   thumbnails, delete).
7. *Goals & tracked metrics editor* (self only) — metric checkboxes, per-metric
   goal inputs, and the "About you" snapshot (height m / sex / age) with the
   hint that BMI & BMR derive from it.
8. *Progress history* — the periods list (range + kind badge + shared
   indicator); tapping one loads it read-only (hide the log form and editors
   for any non-active or aligned period).

**Empty states**: fresh self period → "No measurements yet — log your first
entry below. Once you've logged a metric twice, your trend charts here."
Aligned with no data → "Your nutritionist hasn't recorded measurements yet…".
`comparison` null until two dated entries carry photos.

## 7. Localization

`metrics[].label` arrives **already localized** (driven by the request locale —
send the same locale header/param as the rest of the app, §15). All other §19
payload fields are data (ISO dates, numeric values, enum strings like
`"self"`) — translate enum display strings and all UI copy in the app bundle.
Greek copy for every web string exists in the web `.po` files
(`apps/mehungry_web/priv/gettext/el/LC_MESSAGES/default.po`) — reuse those
translations for consistency (e.g. "Η πρόοδός μου", "Ημερολόγιο",
"Νέα αρχή", "Κοινοποίηση στον διατροφολόγο", "καταγεγραμμένο από εσάς").

## 8. Gotchas / invariants to respect

- **Don't confuse §18 and §19**: `GET /me/progress` (no subpath) is the old
  flat nutritionist-recorded history and still works; the journal is entirely
  under `/me/progress/periods|entries|photos` + `/me/progress/reset`.
- **Upsert semantics**: posting an entry for an existing date *replaces* the
  metrics you send (and keeps the entry's photos). Pre-fill the form from the
  existing entry when the user picks a date that already has one.
- **Derived values refresh on write**: after `PATCH`ing the snapshot
  (height/sex/age), previously logged entries keep their old BMI/BMR; only new
  upserts derive with the new snapshot. (Re-log a date to recompute it.)
- **Goals are metric-keyed and positive**: invalid/blank goal values are
  silently dropped by the server — reflect the response, not the request.
- **404 = not yours**: any cross-user id probe returns 404; don't retry.
- **After §18 actions, refetch**: accepting/declining invitations and
  disconnecting the nutritionist mutate the journal server-side.

## 9. How the server implements it (for reference)

Context `Mehungry.Progress` (tables `progress_periods`, `progress_entries`,
`progress_photos`); the one-active-period invariant is a Postgres partial
unique index. Alignment hooks fire inside `Professionals.accept_invitation/2`
(transactional), `remove_client/2`, `unassign_nutritionist/1`. Chart parity:
`measurement_history_for_period/1` emits the same point shape as the
nutritionist history so one chart component (`MehungryWeb.MeasurementChart`)
renders both. API: `MehungryWeb.Api.V1.ProgressController` + `ProgressJSON`;
upload kind `progress_photo` in `UploadController`. Web UI:
`ProfileLive.Index` (`/profile?tab=progress`). Nutritionist read surface for
shared periods: `ClientDetail` → `shared_journal_panel` via
`Progress.shared_history_for_professional/2`.
