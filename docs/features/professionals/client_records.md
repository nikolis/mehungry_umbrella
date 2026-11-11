# Client Records & Dietary History

How a nutritionist keeps a **client file** (a "patient record" / ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ)
inside m3hungry — the person's identity, a baseline **intake** assessment, and a chronological
timeline of **consultation notes**. Records are created two ways: by **importing** an existing
Google-Sheet CSV export, or **by hand** in-app when onboarding a fresh client. Profiles, booking,
and articles are documented separately in the sibling docs.

> **Localized.** Like the rest of the nutritionist workspace, the client-file editing surfaces and
> timeline render in the nutritionist's language (EN/EL) — the surface is fully `gettext`-wrapped
> and translated. See `docs/implementation/localization.md` ("Done: the nutritionist workspace").

## What this is (and isn't)

A `ProfessionalClient` is **not** the same as a `TutorClientAssignment`. The assignment
(`docs/professionals/professional_profiles.md`, the "My Clients" flow) links a nutritionist to a
registered platform `User` via invitation. A `ProfessionalClient` is a nutritionist-owned file
that **holds the client's PII directly** on top of that link. It **always references a platform
`User`** via `user_id` (**required** — a record is *never headless*); the PII columns carry the
dietary-history detail the bare `User` doesn't.

## Data model (`apps/mehungry/lib/mehungry/professionals/`)

Three schemas, owned by the flat `Professionals` context (migrations `20260904000001..003`):

### `ProfessionalClient` — table `professional_clients`
- `belongs_to :professional, User` (required, the owning nutritionist) and
  `belongs_to :user, User` (**required** — the linked m3hungry account; a record is never
  headless. FK `on_delete: :delete_all` — deleting the user removes the record. Enforced by
  `validate_required` + a `NOT NULL` column, migration `20260920000004`, which also deleted any
  pre-existing headless rows).
- PII: `full_name` (required), `date_of_birth`, `email`, `phone`, `address`, `postal_code`,
  `work_schedule`.
- `has_many :intakes`, `has_many :consultation_notes`.

### `ClientIntake` — table `client_intakes`
A baseline assessment (the intake form filled at the first appointment); `has_many` off the
client keyed by `assessed_on`, so a client can be re-assessed over time.
- **Typed, queryable columns:** `assessed_on`, `height_m`, `weight_kg`, `bmi`,
  `usual_weight_kg`, `ideal_weight_kg`, `adjusted_weight_kg` (floats), `bmr_kcal`, `tdee_kcal`
  (ints), `sex`, `activity_level` (strings), `age` (int), `goal`.
- **Auto-calculated energy figures.** `bmi`, `bmr_kcal` (Mifflin–St Jeor) and `tdee_kcal`
  (BMR × activity factor) are derived from `height_m`/`weight_kg`/`sex`/`age`/`activity_level`
  by the pure `Mehungry.Professionals.Anthropometrics` calculator (also the single source of
  the sex + activity-level `<select>` vocab and factors). The intake `changeset/2` fills any of
  the three that are **blank** on write (safety-net for CSV import / API / first save, never
  overwriting a supplied value); the manual editors recompute them live as the nutritionist
  edits a source field (`phx-change` keyed on `_target`) while leaving a hand-typed override
  alone. `age` is prefilled from the client's `date_of_birth` when a new intake is opened.
- **`details` (JSONB map)** holds the free-form questionnaire (medical history, lifestyle,
  eating behavior) plus a nested `recall_24h` map (the 24-hour recall). The canonical key set +
  display labels live in one place — `Mehungry.Professionals.DietaryHistory.Fields`
  (`detail_labels/0`, `recall_labels/0`) — shared by the read-only view, the editor, and aligned
  with what the CSV parser routes, so imported and hand-authored records carry the same shape.

### `ConsultationNote` — table `consultation_notes`
A clinical progress note for a visit (distinct from `Appointment`; may optionally reference one).
It also carries the per-visit **body measurements** that drive the client progress chart.
- `visit_number` (intentionally not unique — real histories skip/repeat), `visit_date`,
  `modality` (`in_person | phone | online`, via `ConsultationNote.modalities/0`), `body`, `todo`,
  `details`.
- **Measurements** — directly entered: `weight_kg`, `body_fat_percentage` (validated 0–100),
  `waist_cm`, `muscle_mass_kg`, and the optional circumference metrics `hands_cm`, `glutes_cm`,
  `feet_cm` (all floats, each validated `> 0`). **Auto-computed on save**: `bmi` (float) and
  `bmr_kcal` (integer), derived from the note's `weight_kg` + the client's **latest `ClientIntake`**
  (`height_m`/`sex`/`age`) via `Anthropometrics.compute/1`, filling only blanks the nutritionist
  left (never overwriting a typed value; both stay `nil` when the client has no intake). The fill
  lives in `create_consultation_note/1`/`update_consultation_note/2` (context), not the changeset,
  because the inputs span two rows.

### `ClientCondition` — table `professional_client_conditions`
The **structured client↔condition link**: a join row connecting a `ProfessionalClient` to an
existing `Health.Condition`. A client can carry **several** conditions, each only once (unique on
`[:professional_client_id, :condition_id]`). This is the FK association the research layer wanted —
previously a client's conditions lived only as free text inside `ClientIntake.details`
(`hereditary_conditions` etc.), which couldn't be joined on.
- `belongs_to :professional_client` and `belongs_to :condition` (both FKs `on_delete: :delete_all`
  — deleting the client record or the registry condition removes the link; the condition registry
  row itself is untouched).
- Exposed on `ProfessionalClient` as `many_to_many :conditions, Health.Condition` +
  `has_many :client_conditions`.
- **Existing conditions only** — the link always points at a `Health.Condition` picked from the
  registry (`Health.list_conditions/0`); this layer never creates a condition.
- **Nutritionist-only** — the only write path is the nutritionist-gated client Overview (below).
  Consumers/clients never see or edit it (stays inside the YMYL boundary).

## Context API (`professionals.ex`)

- **Records:** `list_client_records/1`, `get_client_record!/2` (scoped to owner),
  `create_client_record/1`, `update_client_record/2`, `delete_client_record/1`,
  `change_client_record/2`.
- **Intakes:** `get_latest_intake/1`, `list_intakes/1`, `create_intake/1`, `update_intake/2`,
  `change_intake/2`.
- **Notes:** `list_consultation_notes/1` (chronological), `create_consultation_note/1`,
  `update_consultation_note/2`, `delete_consultation_note/1`, `change_consultation_note/2`.
- **Progress / measurements:** `measurement_history/1` (per-client dated points, each carrying every
  metric present — `weight_kg`, `body_fat_percentage`, `waist_cm`, `muscle_mass_kg`, `hands_cm`,
  `glutes_cm`, `feet_cm`, `bmi`, `bmr_kcal` — merged from intakes + consultation notes, sorted by
  date);
  `weight_history/1` (the legacy weight-only slice, still used where only weight is plotted);
  `measurement_history_for_user/1` (a **user-scoped**, cross-nutritionist aggregation powering the
  client's own "My progress" chart — pass only the viewer's own id); `measurement_metrics/0`.
- **Lazy file:** `ensure_client_record/2` — fetches the professional's record for a user, creating a
  minimal one if none exists (the single lazy-create shared by the client file and appointment
  measurement logging).
- **Conditions:** `list_client_conditions/1` (linked `Health.Condition`s, name-ordered),
  `add_client_condition/2` (idempotent — a duplicate pair is a no-op via `on_conflict: :nothing`),
  `remove_client_condition/2` (no-op if unlinked, returns `{:ok, count}`).
- **Import:** `import_dietary_history/2` → `DietaryHistory.Importer`.

## CSV import — migrating an existing history

`DietaryHistory.CsvParser` (pure) parses a "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" Google-Sheet export (Greek
labels, EU comma-decimals, Greek dates) into `%{client, intake, consultation_notes}`;
`DietaryHistory.Importer` writes it as a new record + intake + notes in one transaction. Because a
record is never headless, `Importer.import_csv/3` **requires** a `:user_id` opt (returns
`{:error, :user_required}` otherwise). UI: `/nutritionist/clients/import` (folded into
`NutritionistLive.Clients`, **pick the m3hungry client** → upload → preview → confirm); the client
is chosen from the nutritionist's assigned clients (`list_clients/1`) and its account name is the
fallback when the sheet's identity row is blank. `ClientDetail` deep-links here with the client
preselected via `?client_id=`.

## Manual authoring — everything edits on the client Overview

There is **no separate record editor, no "new client" page, and no user picker**: a record is
always reached from a client, so its platform-user association is implied by which client you
opened, and **all editing happens on the client Overview** (`ClientDetail`,
`/nutritionist/clients/:id`). The record is created by `ClientDetail.ensure_record/1` lazily on
the first write (intake, visit, condition, or PII edit). The three editable pieces:

- **Client details (PII)** — the header's **Edit details** button opens a modal
  (`client_details_modal`) with the record's own PII fields (full name, date of birth, email,
  phone, postal code, address, work/schedule) → `Professionals.update_client_record/2`.
  `professional_id`/`user_id` are already set and untouched by a details save; `date_of_birth`
  feeds the age prefill on a new intake.
- **Intake** — edited inline in the Dietary History card (typed anthropometrics via `<.input>`;
  questionnaire + 24h recall as plain `intake[details][…]` textareas so the `details` map casts
  as-is — create if absent, else update the latest), with live BMI/BMR/TDEE recompute on source
  edits (typed outputs are overrides). The schema is `has_many` keyed on `assessed_on`, so a client
  is **re-assessed over time**: **"New assessment"** opens a fresh intake dated today **prefilled
  from the latest** (`prefilled_assessment/2` carries the stable picture forward; its `id` is nil so
  the save creates a second row rather than overwriting). An **assessment-history switcher** (one
  dated chip per assessment, `list_intakes/1`) lets the nutritionist view any past assessment
  **read-only** — only the latest is editable; `@intake` (used by the summary/progress/AI) stays the
  latest.
- **Visits (consultation notes)** — the **+ New visit** modal creates; each expanded visit row
  has **Edit** (reopens the same modal prefilled, covering the full measurement set + appointment
  link) and a confirm-gated **Delete**.

The record page (`NutritionistLive.ClientRecord`, `/nutritionist/records/:id`) is the **printable
clinical document** — the chronological timeline with an `m3hungry client` badge, a **Print / Save
as PDF** action (`window.print()`) and a **Edit on client overview** button. A `@media print`
rule hides the surrounding app chrome and prints only the `#printable` subtree, so it hands cleanly
to a client or a file. Client-file links to it are labelled **"Printable record →"**. Ownership is
enforced on its mount via `get_client_record!(current_user.id, id)` in a rescue (redirect to
`/nutritionist/clients` on miss); the Overview enforces it via the assignment check.

(The former standalone editor, `ClientRecordEditor` at `/nutritionist/records/:id/edit`, was
removed 2026-11-10 — it duplicated the intake form and condition picker, and its note form had
drifted behind the visit modal's measurement set. Note the Overview resolves the **most recent**
record per user, so older duplicate records from repeated CSV imports are read-only.)

## Health conditions — recording the structured link

A nutritionist links conditions on the **User Overview** (`ClientDetail`,
`/nutritionist/clients/:id`), driven by the `add_condition` / `remove_condition` events
(→ `Professionals.add_client_condition/2` / `remove_client_condition/2`, reassigning the chip
list — no changeset round-trip). Conditions render as **one more basic field in the Dietary
History card**: a "Conditions" label, the linked conditions as chips, and a minimal
`+ Add condition` `<select>`. Adding the first condition **lazily creates** the
`ProfessionalClient` record (via `ensure_record/1`) just like recording the first visit.

Because the picker is a fixed list of registry conditions (`Health.list_conditions/0`, minus the
already-linked ones), a nutritionist can only ever link **existing** conditions, never type a new
one. The read-only record page (`ClientRecord`) renders the linked conditions as read-only chips.

**The payoff — per-condition research notes.** Each condition chip in the overview carries a
**"Notes"** deep-link to `/nutritionist/research/notes?condition_id=<id>`, which scopes the
nutritionist's **"My notes"** page (`MyResearchNotes`) to just that condition's saved notes
(`ResearchNotes.list_for_user_and_condition/2`), with an empty state that links straight to the
condition's research when nothing is saved yet. This is the Phase 3 payoff of the research layer's
**Suggested Notes** feature, which was blocked on exactly this structured link (see
[`research_notes.md`](research_notes.md) §6).

## The client file — tabbed by job

The per-client file (`NutritionistLive.ClientDetail`, `/nutritionist/clients/:id`, keyed on the
platform **`User` id**, reached via **Overview** on the clients roster) is organised into four
tabs (`?tab=`, driven by `handle_params`, each one a distinct nutritionist job — `patch` links so
back/forward/deep-links work):

- **Overview** (today's work) — the **session ribbon**, the summary strip, the progress trend, the
  shared journal, the visits accordion, and appointment history.
- **Record** (the clinical file) — the Dietary History intake + conditions, and the client's
  onboarding answers.
- **Messages** — the full-height thread (its tab label carries the unread badge).
- **Planning** — the AI meal-plan assistant, the "assign a saved plan" tool (with preview), the
  meal-plan history, and the meal-plan ratings.

When an **appointment with this client falls within the next ~48h** (`next_session/1`, derived
in-memory from the already-loaded appointment list), the Overview opens with a paprika-edged
**session ribbon**: when it is / what kind (online if the appointment has a meeting link) / the last
visit's date + agreed next-steps / a **Log visit** button — the whole pre-session prep compressed to
one glance. No upcoming appointment → no ribbon.

### Overview — summary strip + visits accordion

The Overview opens with a
single **at-a-glance summary strip**: six KPI cards — Goal, Weight (latest reading + since-baseline
delta vs. the intake's ideal weight), BMI (healthy-band dot), **Energy** (TDEE headline with BMR
underneath — one card, since they are one concept), Last visit, and **Next steps** (the last visit's
`todo`, surfaced for pre-session prep instead of being buried in the timeline) — plus a compact
**reference line** underneath with the latest intake's anthropometrics (sex, age, activity, height,
weight at intake, ideal/usual/adjusted weight; only filled fields show). The **Goal card edits
inline** (`edit_goal`/`save_goal`): one sentence shouldn't open the whole intake form, so the save
writes just `goal` onto the latest intake (lazily creating the record + a goal-only intake on first
use). This is the **one**
metrics overview on the page — the Dietary History card (on the **Record** tab) deliberately repeats
none of it and holds only the qualitative record (assessed date, conditions, goal, questionnaire,
24h recall). The **Record** tab surfaces the client's dietary-history record **grouped by lifecycle**
(`Fields.detail_groups/0` — unit-tested to cover every questionnaire key): conditions and the
**clinical-flag chips** (allergies, intolerances, aversions, medications — the every-visit safety
layer) stay always visible at the top of the card, and everything else folds into native
`<details>` sections with filled-field counts — **Lifestyle & eating habits**, **Medical
background**, **Story & goals** (opens with the full goal text), **24-hour recall**. The intake
edit form and the read-only record page mirror the same group headings
(`ClientDetailComponents.detail_field_groups/0`). While the intake is being **edited**, the client's
own **onboarding answers sit beside the form** with a per-answer **Copy** button (the `Copy` hook) so
the nutritionist lifts the client's exact words into the matching field instead of re-typing them.
`get_client_record_by_user/2` resolves the
`ProfessionalClient` for `(professional_id, user_id)` (most recent if several); its consultation
notes render as a **"Client Record — Visits"** accordion inside a scrollable
(`max-h-96 overflow-y-auto`) container — each row is a native `<details>` disclosure
(keyboard/screen-reader accessible) showing basic info (visit number, date, modality, weight), with
the full body/todo revealed on expand; the newest visit opens by default. A **View full dietary history**
link deep-links to `/nutritionist/records/:id`. A **+ New visit** button opens a `<.modal>` form
(`save_visit`) that **lazily creates** the `ProfessionalClient` (from the client `User`'s
name/email) on the first visit if none exists, then `create_consultation_note/1`. The visit form
captures the full measurement set (weight, body fat %, waist, muscle mass); BMI/BMR are filled
automatically from the client's latest intake. The modal never covers its own context: the
**previous visit** rides along in a read-only reference pane (its measurements, note excerpt and
agreed to-dos) and every measurement input carries a **"last: X"** hint — the delta is the point of
measuring, so a new value is typed against a reference, not into a void (when editing an existing
visit, the reference is the latest *earlier* visit, never the one being edited). New visits are
numbered **`max(visit_number) + 1`**, not `count + 1`, so deleting a middle visit never re-issues a
duplicate "Visit N". Linking an appointment stamps the visit date from it and, when that appointment
carries a meeting link, also prefills the **online** modality (`prefill_from_appointment`).

## Progress tracking — measurement chart

The overview renders a **Progress dashboard** below the visits (shared `MehungryWeb.MeasurementChart`,
reused on the client's own `/profile`). `measurement_history/1` feeds a row of **KPI cards** — one per
metric with **≥2 dated readings** — each showing the current value, the since-baseline delta (tinted
good/bad/neutral by whether the change is the right direction for that metric) and a sparkline. Clicking
a card focuses the **detail trend chart** below it for that metric (one metric at a time — the units are
incompatible). The detail chart is a **hand-built server-side SVG** (area + line, intake vs. visit points
distinguished, latest reading emphasized) — **not VegaLite**; it draws a dashed **goal line** and a shaded
**healthy-range band** when `measurement_context/1` supplies the grounding intake values (`ideal_weight_kg`
→ weight goal; `height_m` → healthy weight range via BMI 18.5–24.9; `sex` → body-fat band; BMI uses the
universal 18.5–24.9 band). The dashboard is gated on ≥2 points for at least one metric; otherwise an
empty state shows.

Measurements can be logged two ways, both writing a `ConsultationNote`:
1. **From the client file** — the **+ New visit** form (above).
2. **From the meeting** — a **"Log measurement"** button in the appointment detail modal on
   `/nutritionist/appointments` (`NutritionistLive.AppointmentCalendar`). It resolves the appointment's
   client `User` → `ProfessionalClient` via `ensure_client_record/2` (lazy-create) and opens a
   measurement form whose saved note is pre-linked to that `appointment_id`. The button is **hidden
   for external-client appointments** (no `client_id` → no platform user → no clinical file possible).
   This surface enforces **one note per meeting**: re-logging the same appointment re-opens the form
   **pre-filled** with the existing note and **updates** it on save (not a new row), via
   `Professionals.upsert_consultation_note_for_appointment/1`, which also consolidates any pre-existing
   duplicates down to the latest note (deleting the rest in the same transaction).

Either way, a note's `appointment_id` is **ownership-validated at write time**
(`Professionals` create/update → `validate_note_appointment/1`): the linked appointment must belong
to the same professional **and** be booked with the record's platform user — a crafted form payload
can't attach (and therefore render, via the `:appointment` preload) another professional's
appointment.

**Client-facing view.** The client sees their own progress on their profile (`/profile` →
**My progress** tab, owner-only). Since 2026-11-07 that tab is the period-based **progress
journal** (`Mehungry.Progress`, see [`../progress_journal.md`](../progress_journal.md)): the
nutritionist-recorded history renders inside the client's **nutritionist-aligned period**
(date-filtered `measurement_history_for_user/1` — still aggregated across all nutritionists,
`source: intake | visit`), alongside their own past self-tracked periods. The read path uses only
`current_user.id` and the tab is rendered only on the owner's own `:index` profile (never on a
`:show` of someone else) — a client only ever sees their own body data.

**Shared self-tracking journal (read-only).** When the client opts to **share** one of their own
journal periods, the client file shows a **"Client's own journal (shared with you)"** dashboard
(`shared_journal_panel`, above the clinical panels): the client's self-logged measurements on the
same `MeasurementChart`, `source: self`. Strictly read-only; the client can revoke at any time;
`Progress.shared_history_for_professional/2` verifies the viewer is the assigned nutritionist.

## Messages — honest read receipts

The **Messages** tab carries the client↔nutritionist thread (shared `<.message_thread>`). The thread
is **not** marked read when the client file is opened on another tab — a nutritionist glancing at a
weight must never fire a "seen" receipt they didn't earn. The read receipt is **opening the Messages
tab**: `handle_params` runs `mark_thread_read/3` when `tab == "messages"`, gated on
`connected?(socket)` (so the disconnected HTTP render / link-prefetch / reconnect reload never fires
it) and skipped when nothing is unread. While the nutritionist is on another tab, an incoming message
appends and **increments the unread badge** (on the Messages tab label, plus a paprika chip in the
client header that patches to `?tab=messages`); while the Messages tab is open, new messages are read
as they arrive (`messages_visible?`, set true by `apply_tab`, gates the live `handle_info`). The
unread count for the thread is `Professionals.count_unread_in_thread/3`.

## The payoff — the client file feeds the AI meal-plan draft

The record is not just a filing cabinet: when the nutritionist clicks **"Draft 7-day Plan"** on the
Planning tab, the `NutritionistAgent` reads the whole file so the draft honours it. Progress streams
live over PubSub; if the nutritionist navigates away and re-mounts mid-draft, the panel **resumes
its running state** (`NutritionistAgentWorker.running?/2` checks Oban for an active job for this
professional+client on mount) instead of flashing the idle form. Its
`get_client_record` tool merges the latest **intake** (goal, TDEE → the plan's `calorie_target`),
the linked **conditions**, the latest **consultation note**, and the client's own `UserProfile`
(diet, `avoid_foods`) into one brief with a unified **`avoid` list** — personal avoid foods +
intake allergies/intolerances + **condition-implicated foods** (via `Health.ingredients_for_condition/2`).
A second tool, `get_assigned_plan`, reads any meals the nutritionist already assigned to the week
and the agent **leaves those cells untouched** (skip-filled-slots). So filling in a client's
intake/conditions and assigning part of a week both directly shape (and constrain) the AI draft —
see [`../../implementation/ai/ai_agents.md`](../../implementation/ai/ai_agents.md) §NutritionistAgent.

## Files

**Core (`apps/mehungry`)**
- `lib/mehungry/professionals/{professional_client,client_intake,consultation_note,client_condition}.ex`
- `lib/mehungry/professionals/dietary_history/{csv_parser,importer}.ex`,
  `dietary_history/fields.ex` (shared label lists)
- `lib/mehungry/professionals.ex` — record/intake/note/condition/message context functions
  (`list_intakes/1`, `count_unread_in_thread/3`, …)
- `lib/mehungry/oban_workers/nutritionist_agent_worker.ex` — `running?/2` (AI-draft resume on re-mount)
- `priv/repo/migrations/20260904000001_*`, `..002_*`, `..003_*`,
  `20261027150000_create_professional_client_conditions.exs`

**Web (`apps/mehungry_web`)**
- `lib/mehungry_web/live/nutritionist_live/client_detail.ex` — the client file: tabbed
  (Overview/Record/Messages/Planning via `?tab=`), session ribbon, inline goal, intake re-assessment,
  visits modal, messages (tab-activation read receipt), plan assign + preview, AI draft
- `lib/mehungry_web/live/nutritionist_live/client_detail_components.ex` — its presentational components
- `lib/mehungry_web/live/nutritionist_live/client_record.ex` — printable `/nutritionist/records/:id`
- `assets/js/hooks.js` — `Copy` (onboarding-answer copy), `EnterToSend`
- `lib/mehungry_web/router.ex`

**Tests**
- `apps/mehungry_web/test/mehungry_web/live/nutritionist_live/client_detail_test.exs`
