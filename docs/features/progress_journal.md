# Progress Journal (self-tracking)

> Status: **shipped 2026-11-07** · Web (`/profile?tab=progress`) + mobile API (spec §19)

## What it is, for whom

The **user's own** body-progress tracker — for people **without a nutritionist**
(and as the continuous home of their progress when they get one). A user sets
personal goals, picks which metrics they care to monitor (maybe only weight, or
weight + waist), logs dated diary entries (measurements + a free-text note +
optional body photos), and watches their trend on the same progress dashboard
the nutritionist tooling uses. They can **reset and start over from 0** at any
time without losing anything — and opt-in to **sharing** their journal with
their assigned nutritionist.

This completes the progress story: previously the `/profile` "My progress" tab
only showed **nutritionist-recorded** measurements (`ClientIntake` +
`ConsultationNote`), so a user with no nutritionist saw an empty state forever.

## Periods — the core concept

Progress is organised into **periods**, identified by their date range
("22 Oct – 22 Dec", "22 Dec – ongoing"). Exactly one period is active per user
(DB-enforced). Two kinds:

- **Self-tracked** (`self`): the user logs their own entries. Goals, tracked
  metrics, and an optional height/sex/age snapshot (so BMI — and BMR when age
  is known — derive automatically) live on the period.
- **Nutritionist-aligned** (`nutritionist_aligned`): opened **automatically**
  when the user is assigned a nutritionist (accepting an invitation — including
  a nutritionist *switch*). The previous period closes, self-logging pauses,
  and this period's chart is fed by the nutritionist's intake/visit
  measurements **up to the period's end** (deliberately no lower date bound —
  a nutritionist often holds measurements predating the assignment, and the
  aligned chart must match the old flat "My progress" view). The user sees a
  notice ("your nutritionist tracks your progress now; your earlier history is
  saved below"). When the assignment ends (either side), the aligned period
  closes and a fresh self period opens — self-tracking resumes seamlessly.

**Reset ("Start over")** closes the active self period today and opens a fresh
one (same tracked metrics + snapshot, goals cleared). Closed periods — with
all their entries and photos — stay forever in the **Progress history** list,
each openable read-only.

## Diary, chart, photos

- **Diary**: one entry per date (re-logging a day updates it) with the tracked
  measurements + a note. Presented newest-first as a diary; the trend chart
  reads the same entries oldest-first. The log form round-trips its in-flight
  values through an `entry_draft` assign (`validate_entry`) because the photo
  auto-upload re-renders the form mid-edit — unbound inputs would silently
  reset and the entry would save empty next to its photo.
- **Chart**: the Progress tab **leads with a multi-series overlay chart**
  (`MehungryWeb.ProgressOverlayChart`, server-SVG) plotting the logged body
  measurements and — toggleable onto the **same diagram** — per-day
  **nutrition-intake series from the user's logged meals**: Total Fat,
  Polyunsaturated / Monounsaturated / Trans Fat, Carbohydrates, Sugars, Fiber,
  Protein, Energy (kcal). Because the series span incompatible units
  (kg/%/cm/g/kcal), each line is **min–max normalized to its own range** — the
  plot compares trends, and the legend carries each series' **latest absolute
  value**; with exactly one series selected the y-axis shows that series' real
  numbers. Selection is multi-select: the body-metric KPI cards and a
  "From your logged meals" chip row both toggle series on/off
  (`toggle_series` event, `MapSet` of keys, default = weight).
  Nutrition values come from the calendar's exact pipeline
  (`History.daily_nutrition_history/3` →
  `list_calendar_user_meals` + `format_user_meals` +
  `NutrientUtils.summarize_meals_nutrients/nutrition_series_summary` — REST↔
  LiveView parity, numbers always match the calendar), windowed to the
  **viewed period's own range** (`started_on` → `ended_on`/today) so meals
  logged before the period stay off its diagram; a period with no lower bound
  falls back to a trailing 90-day window. The chart's **date axis is widened
  to the period's range** too (union with the data — aligned-period history
  from before `started_on` stays on-plot), so the diagram always spans the
  whole period. Days with no
  logged meals are **skipped** (the line bridges the gap — no zero dips).
  Goal lines/healthy bands don't transfer to a normalized plot: goals stay
  visible as the header chips, and absolute deltas live in the KPI cards /
  Before → Now. The nutritionist `ClientDetail` keeps the original
  single-metric `MeasurementChart` dashboard unchanged (the two modules share
  geometry constants so `photo_strip` pins align — mirror comments in both).
- **Photos**: up to 4 per entry. Thumbnails are **pinned under the trend chart
  at their entry's date** (same x-axis math as the SVG), and the period's
  earliest/latest photo-carrying entries render as a **Before → Now**
  comparison pair with the measurement deltas between them. Tapping any photo
  opens a lightbox. Deleting photos/entries removes the storage objects too.

## Photo privacy (private by default, shareable by choice)

Body photos are sensitive (GDPR Art. 9-adjacent), so they are **never**
world-readable:

- Objects live in the **private** Supabase bucket (`bucket: :private` through
  `Mehungry.Storage`; see
  `docs/implementation/infrastructure/object_storage.md`). Only the
  private-bucket `storage_key` is persisted — no permanent URL exists.
- Every read surface (diary thumbnails, chart photo strip, Before → Now,
  lightbox, all §19 payloads) serves **short-lived signed URLs (~1 h)**,
  derived in exactly one place: `Progress.photo_url/1` / its bulk signer
  (REST↔LiveView parity — web and API can't drift).
- **Opt-in sharing**: from the lightbox (web) or
  `POST /api/v1/me/progress/photos/:id/share`, the owner can create a public
  share link — `https://…/shared/photos/<token>`, a crypto-random token that
  302s to a fresh ~10-min signed URL on each visit. **Unshare deletes the
  token**, so the link dies instantly (already-issued signed URLs lapse within
  minutes). Photos are visible to no one else — not even a nutritionist the
  *period* is shared with (the shared journal panel carries measurements only).
- Legacy photos uploaded to the public bucket before this change are moved by
  the one-off `mix progress.migrate_photos` sweep
  (`Mehungry.Progress.PhotoMigration`).

## Sharing with the nutritionist

Off by default. The user can mark a period **"Share with nutritionist"**
(requires an assignment; revocable any time). The nutritionist's client file
(`/nutritionist/clients/...`) then shows a read-only **"Client's own journal
(shared with you)"** dashboard above the clinical panels — no write surface,
and `Progress.shared_history_for_professional/2` verifies the caller *is* the
assigned nutritionist.

## Surfaces

- **Web**: `/profile?tab=progress` (owner-only tab, fully localized EN/EL).
- **Mobile**: `/api/v1/me/progress/periods…` — spec
  `docs/implementation/new_dec_specs/mobile_api_spec.md` **§19** (14 routes:
  periods CRUD/bootstrap, reset, period share/unshare, entries upsert/delete,
  photo attach/delete, photo share/unshare; photos upload via the §11 presign
  flow, `kind: "progress_photo"` → private bucket). §18's
  nutritionist-sourced `GET /me/progress` is unchanged. Public (no-auth)
  `GET /shared/photos/:token` resolves photo share links.

## Implementation map

- Context: `Mehungry.Progress` (`progress.ex` + `progress/{period,entry,photo}.ex`;
  tables `progress_periods` / `progress_entries` / `progress_photos`).
  Chart parity rule: `measurement_history_for_period/1` emits the exact point
  shape `Professionals.measurement_history_for_user/1` does (`source: :self`).
- Alignment hooks: `Professionals.accept_invitation/2` (transactional;
  also covers nutritionist switches), `remove_client/2`,
  `unassign_nutritionist/1` → `Progress.on_nutritionist_{assigned,unassigned}`.
  `create_managed_client/2` deliberately does **not** open a period.
- Web: `ProfileLive.Index` progress tab; `MeasurementChart` gained `:self`
  source, goal-from-`context.goals`, `photo_strip/1`, `before_now/1`.
  Nutritionist read surface: `ClientDetail` + `shared_journal_panel`.
- API: `Api.V1.ProgressController` + `ProgressJSON`; `UploadController` kind
  `progress_photo` (private bucket); public `SharedPhotoController`
  (`/shared/photos/:token`).
