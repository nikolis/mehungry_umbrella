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
  (ints), `goal`.
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

## Context API (`professionals.ex`)

- **Records:** `list_client_records/1`, `get_client_record!/2` (scoped to owner),
  `create_client_record/1`, `update_client_record/2`, `delete_client_record/1`,
  `change_client_record/2`.
- **Intakes:** `get_latest_intake/1`, `list_intakes/1`, `create_intake/1`, `update_intake/2`,
  `change_intake/2`.
- **Notes:** `list_consultation_notes/1` (chronological), `create_consultation_note/1`,
  `update_consultation_note/2`, `delete_consultation_note/1`, `change_consultation_note/2`.
- **Import:** `import_dietary_history/2` → `DietaryHistory.Importer`.

## CSV import — migrating an existing history

`DietaryHistory.CsvParser` (pure) parses a "ΔΙΑΤΡΟΦΟΛΟΓΙΚΟ ΙΣΤΟΡΙΚΟ" Google-Sheet export (Greek
labels, EU comma-decimals, Greek dates) into `%{client, intake, consultation_notes}`;
`DietaryHistory.Importer` writes it as a new record + intake + notes in one transaction. Because a
record is never headless, `Importer.import_csv/3` **requires** a `:user_id` opt (returns
`{:error, :user_required}` otherwise). UI: `/nutritionist/records/import` (`NutritionistLive.Records`,
**pick the m3hungry client** → upload → preview → confirm); the client is chosen from the
nutritionist's assigned clients (`list_clients/1`) and its account name is the fallback when the
sheet's identity row is blank.

## Manual authoring — onboarding a fresh client

`/nutritionist/records/new` and `/nutritionist/records/:id/edit` →
`MehungryWeb.NutritionistLive.ClientRecordEditor`. Modeled on `ArticleEditor`/`ProfileEdit`
(incremental persistence, raw changesets in assigns, `<.input>` + local `<.labeled>`,
`validate`/`save` events). Reached from a **+ New client** button on the records roster.

- **`:new`** — the **client-details** form plus a **required association control**: pick the
  linked m3hungry `User` from the nutritionist's assigned clients (`list_clients/1`) **or** look up
  any registered user by account email (`Accounts.get_user_by_email/1`). Resolving either sets
  `user_id` and prefills `full_name`/`email` from the `User`. Saving without a linked user is
  refused (a record is never headless).
  - On save: `create_client_record/1` (with `professional_id` + `user_id`), then navigate into `:edit`.
- **`:edit`** — three stacked sections: the client-details form again (attach/detach a platform
  user anytime); one **intake** form (typed anthropometrics via `<.input>`; questionnaire + 24h
  recall as plain `intake[details][…]` inputs so the `details` map casts as-is — create if absent,
  else update the latest); and a repeatable **consultation notes** list (add / edit / delete, each
  its own form with a hidden `_id`).

Ownership is enforced on mount via `get_client_record!(current_user.id, id)` in a rescue
(redirect to `/nutritionist/records` on miss). The read-only record page
(`NutritionistLive.ClientRecord`, `/nutritionist/records/:id`) has an **Edit** link and an
`m3hungry client` / `External` badge driven by `user_id`.

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
- `lib/mehungry/professionals/{professional_client,client_intake,consultation_note}.ex`
- `lib/mehungry/professionals/dietary_history/{csv_parser,importer}.ex`,
  `dietary_history/fields.ex` (shared label lists)
- `lib/mehungry/professionals.ex` — record/intake/note context functions
- `priv/repo/migrations/20260904000001_*`, `..002_*`, `..003_*`

**Web (`apps/mehungry_web`)**
- `lib/mehungry_web/live/nutritionist_live/{records,client_record,client_record_editor,client_detail}.ex`
  (`client_detail` = the User Overview, which also embeds the visits accordion + new-visit modal)
- `lib/mehungry_web/router.ex`

**Tests**
- `apps/mehungry_web/test/mehungry_web/live/nutritionist_live/client_record_editor_test.exs`
