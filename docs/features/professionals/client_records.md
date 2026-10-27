# Client Records & Dietary History

How a nutritionist keeps a **client file** (a "patient record" / ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ)
inside m3hungry — the person's identity, a baseline **intake** assessment, and a chronological
timeline of **consultation notes**. Records are created two ways: by **importing** an existing
Google-Sheet CSV export, or **by hand** in-app when onboarding a fresh client. Profiles, booking,
and articles are documented separately in the sibling docs.

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
- `visit_number` (intentionally not unique — real histories skip/repeat), `visit_date`,
  `modality` (`in_person | phone | online`, via `ConsultationNote.modalities/0`), `body`, `todo`,
  `weight_kg`, `details`.

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
- **Nutritionist-only** — the only write path is the nutritionist-gated record editor (below).
  Consumers/clients never see or edit it (stays inside the YMYL boundary).

## Context API (`professionals.ex`)

- **Records:** `list_client_records/1`, `get_client_record!/2` (scoped to owner),
  `create_client_record/1`, `update_client_record/2`, `delete_client_record/1`,
  `change_client_record/2`.
- **Intakes:** `get_latest_intake/1`, `list_intakes/1`, `create_intake/1`, `update_intake/2`,
  `change_intake/2`.
- **Notes:** `list_consultation_notes/1` (chronological), `create_consultation_note/1`,
  `update_consultation_note/2`, `delete_consultation_note/1`, `change_consultation_note/2`.
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

## Manual authoring — editing the full record

There is **no separate "new client" page and no user picker**: a record is always reached from a
client, so its platform-user association is implied by which client you opened. The file is created
by `ClientDetail.ensure_record/1` (lazily on first intake/visit, or eagerly via the **Open full
record** button) and then edited at `/nutritionist/records/:id/edit` →
`MehungryWeb.NutritionistLive.ClientRecordEditor` (`:edit` only). Modeled on
`ArticleEditor`/`ProfileEdit` (incremental persistence, raw changesets in assigns, `<.input>` +
local `<.labeled>`, `validate`/`save` events).

Three stacked sections: the **client-details** form (editable PII — `professional_id`/`user_id` are
already set and untouched by a details save); one **intake** form (typed anthropometrics via
`<.input>`; questionnaire + 24h recall as plain `intake[details][…]` inputs so the `details` map
casts as-is — create if absent, else update the latest); and a repeatable **consultation notes**
list (add / edit / delete, each its own form with a hidden `_id`).

Ownership is enforced on mount via `get_client_record!(current_user.id, id)` in a rescue
(redirect to `/nutritionist/clients` on miss). The read-only record page
(`NutritionistLive.ClientRecord`, `/nutritionist/records/:id`) has an **Edit** link and an
`m3hungry client` badge.

## Health conditions — recording the structured link

A nutritionist links conditions in **two** nutritionist-gated places, both driven by the same
`add_condition` / `remove_condition` events (→ `Professionals.add_client_condition/2` /
`remove_client_condition/2`, reassigning the chip list — no changeset round-trip):

- **User Overview** (`ClientDetail`, `/nutritionist/clients/:id`) — the primary surface. Conditions
  render as **one more basic field in the Dietary History card** (right under the intake
  Sex/Age/…/TDEE metrics): a "Conditions" label, the linked conditions as chips, and a minimal
  `+ Add condition` `<select>`. Adding the first condition **lazily creates** the `ProfessionalClient`
  record (via `ensure_record/1`) just like recording the first visit, so the nutritionist never has
  to open the full editor first.
- **Record editor** (`ClientRecordEditor`, `/nutritionist/records/:id/edit`) — the same picker in a
  dedicated "Health conditions" section between the client-details and intake forms.

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

## User Overview integration — visits accordion

The per-client **User Overview** (`NutritionistLive.ClientDetail`, `/nutritionist/clients/:id`,
keyed on the platform **`User` id**, reached via **Overview** on the clients roster) surfaces the
client's dietary-history record inline. `get_client_record_by_user/2` resolves the
`ProfessionalClient` for `(professional_id, user_id)` (most recent if several); its consultation
notes render as a **"Client Record — Visits"** accordion inside a scrollable
(`max-h-96 overflow-y-auto`) container — each row shows only basic info (visit number, date,
modality, weight) with the full body/todo revealed on expand via client-side `JS.toggle` +
chevron `JS.toggle_class("rotate-180")` (no server round-trip). A **View full dietary history**
link deep-links to `/nutritionist/records/:id`. A **+ New visit** button opens a `<.modal>` form
(`save_visit`) that **lazily creates** the `ProfessionalClient` (from the client `User`'s
name/email) on the first visit if none exists, then `create_consultation_note/1`.

## Files

**Core (`apps/mehungry`)**
- `lib/mehungry/professionals/{professional_client,client_intake,consultation_note,client_condition}.ex`
- `lib/mehungry/professionals/dietary_history/{csv_parser,importer}.ex`,
  `dietary_history/fields.ex` (shared label lists)
- `lib/mehungry/professionals.ex` — record/intake/note/condition context functions
- `priv/repo/migrations/20260904000001_*`, `..002_*`, `..003_*`,
  `20261027150000_create_professional_client_conditions.exs`

**Web (`apps/mehungry_web`)**
- `lib/mehungry_web/live/nutritionist_live/{records,client_record,client_record_editor,client_detail}.ex`
  (`client_detail` = the User Overview, which also embeds the visits accordion + new-visit modal)
- `lib/mehungry_web/router.ex`

**Tests**
- `apps/mehungry_web/test/mehungry_web/live/nutritionist_live/client_record_editor_test.exs`
