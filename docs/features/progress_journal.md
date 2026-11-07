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
  reads the same entries oldest-first.
- **Chart**: the shared `MehungryWeb.MeasurementChart` server-SVG dashboard
  (KPI cards + focused trend). Self-logged points get their own style/legend
  ("logged by you"); the user's **per-metric goals draw dashed goal lines**
  (any metric — not just weight).
- **Photos**: up to 4 per entry. Thumbnails are **pinned under the trend chart
  at their entry's date** (same x-axis math as the SVG), and the period's
  earliest/latest photo-carrying entries render as a **Before → Now**
  comparison pair with the measurement deltas between them. Tapping any photo
  opens a lightbox. Deleting photos/entries removes the storage objects too.

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
  `docs/implementation/new_dec_specs/mobile_api_spec.md` **§19** (12 routes:
  periods CRUD/bootstrap, reset, share/unshare, entries upsert/delete, photo
  attach/delete; photos upload via the §11 presign flow, `kind:
  "progress_photo"`). §18's nutritionist-sourced `GET /me/progress` is
  unchanged.

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
  `progress_photo`.
