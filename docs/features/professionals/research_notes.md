# Design — Suggested Notes (per-nutritionist research notes)

> Status: **Phases 1–2 SHIPPED (2026-10-27); Phase 3 (client surfacing) not started.** Builds
> directly on the nutritionist research search (`docs/features/professionals/research_search.md`).
> Phasing in §7; §6 (surfacing) is deliberately left open — the user asked to "evaluate later where
> this is surfaced."

## 1. Goal

Turn the research search's read-only **extracted findings** into a lightweight, personal
**notes** workflow for the nutritionist:

1. **Rename** the per-paper "Show N extracted findings" disclosure to **"Suggested notes (N)"**.
2. **Clicking a suggested note opens the paper text** at the exact passage (the in-app reader,
   scrolled + highlighted), instead of the current PubMed-abstract link.
3. Each suggested note has a **Save** action; the nutritionist can also **write their own note**
   in a text box.
4. **Saved notes (suggested or custom) persist per nutritionist** and are shown back to them later
   — the first concrete case named: *when one of their clients has this condition*. Exactly where
   that surfacing lives is **TBD (§6)**.

## 2. Current state (what we're changing)

- `MehungryWeb.NutritionistLive.ResearchCondition` renders each paper card with a native
  `<details class="group/claims">` labelled **"Show N extracted findings"** (`show_findings_label/1`),
  listing `visible_claims/1` — each claim as `subject → predicate → object` + the verbatim
  `evidence[].quoted_text`, with a **"source"** link to **PubMed**
  (`pubmed_url/1`). Claims come from `StudyAnalysis.claims` (jsonb; see shape below).
- `MehungryWeb.NutritionistLive.ResearchPaper` (the reader) already renders the full text with
  per-paragraph anchors `#par-<paragraph_id>` and inline `<mark>` highlighting of claim evidence
  spans (`Literature.full_text_for_reader/1`). **The deep-link target already exists** — we just
  don't point the findings at it yet.
- Nothing about claims is persisted per user today; the page is read-only.

**Claim jsonb shape** (one element of `StudyAnalysis.claims`), the raw material of a suggested note:

```
%{
  "claim_id"       => "…",          # stable id within the paper's analysis
  "subject_label"  => "Dietary fiber",
  "predicate"      => "improves",
  "object_label"   => "Remission",
  "polarity"       => "positive" | "negative",
  "certainty"      => "asserted" | "hedged",
  "position"       => "food_related" | "general_science" | "wrong" | "ignore" | nil,  # admin curation
  "evidence"       => [%{"quoted_text" => "…", "paragraph_id" => "…", "section_id" => "…",
                         "start_char" => _, "end_char" => _}]
}
```

## 3. UX

### 3a. The card (`ResearchCondition`)
- Disclosure relabelled **"Suggested notes (N)"** / "Hide suggested notes" (the `group/claims`
  `<details>` stays; only copy + per-row affordances change).
- Each **suggested note** row:
  - prose line (subject → predicate → object, polarity tint) + the verbatim quote — as today;
  - **"Open in text"** → the reader at the claim's first `evidence[].paragraph_id`
    (`/nutritionist/research/:condition_id/paper/:study_id#par-<paragraph_id>`), falling back to
    PubMed only when the paper has no full text;
  - **Save** (bookmark/star toggle) → persists it as the nutritionist's note (§4). Reflects a
    "Saved" state when already saved.
- A **"+ Write your own note"** row → a `<textarea>` + Save → persists a **custom** note attached
  to this study + condition.

### 3b. The reader (`ResearchPaper`) — ✅ SHIPPED 2026-10-27
- A **floating, independent notes widget** (fixed bottom-right, collapsible) sits over the full-text
  reader. The paper's **suggested notes** are always present as a **collapsed-by-default, expandable
  `<details>` list** ("Suggested notes (N)") — each row a Save bookmark toggle + a same-page `#par-`
  jump to its highlighted span — and it offers **"Write your own note"**.
- "Write your own note" enters a **selection mode**: the article gets a text cursor
  (`data-note-mode="true"` + a `ring` affordance), and the next passage the nutritionist highlights
  is captured by the `NoteSelection` JS hook (`assets/js/hooks.js`) — it reads `window.getSelection()`
  + the enclosing `[id^="par-"]` / `[id^="sec-"]` anchors and pushes `select_passage`. The selected
  passage becomes the note's **sub-text** (`quoted_text`); the nutritionist types the **title**
  (`body`) by hand and saves. Persisted as a `custom` note carrying the paragraph/section anchor so
  "My notes" can deep-link back.
- The widget also shows a **"Your notes (N)"** section — the nutritionist's existing notes for *this
  paper* (`ResearchNotes.list_for_user_and_study/2`, both saved suggestions + custom), each with its
  sub-text and an inline delete. It refreshes from the DB after every save/delete
  (`refresh_notes/1`), so a just-written note appears immediately instead of only via a flash. Each
  note's **title is itself a link** (`note_anchor/1` → `#par-<paragraph_id>`) that scrolls the reader
  to its marked paragraph, where the passage is highlighted (below).
- **Deep-link + inline highlight back to the marked text.** A custom note from a selection stores the
  enclosing `paragraph_id` (+ `section_id`) — enough for the `#par-<paragraph_id>` deep-link ("My
  notes" → "Open in text"). On the reader, each such note's marked passage is **highlighted inline
  the same way claims are** (an `<mark>`, accent-tinted `bg-accent-400/30` to stand apart from the
  basil/paprika claim spans): the reader re-locates the stored `quoted_text` within its paragraph
  with a **whitespace-tolerant** search (`locate/2` — the quote is whitespace-collapsed by the
  `NoteSelection` hook at save, the paragraph keeps original spacing) and unions those note spans
  with the claim spans in the shared segment builder. So no character offsets are stored (robust to
  re-rendering) and no schema change was needed.

### 3c. The nutritionist's notes (new surface — Phase 2)
- A **"My notes"** list (route under the `:nutritionist` live_session) of saved notes, grouped by
  condition then study, each linking back to the source passage. This is the always-available
  "present to them at different times" home, independent of any client.

## 4. Data model (proposed)

A per-user note, either a saved suggestion (provenance into a claim) or a free-text custom note.
Owned directly by the nutritionist `User` (mirrors the `user_recipes` per-user pattern, but richer).

**New table `research_notes`** → `Mehungry.Professionals.ResearchNote`
(context `Mehungry.Professionals.ResearchNotes`; alternative home: a new `Mehungry.ResearchNotes`):

| Field | Type | Notes |
|---|---|---|
| `user_id` | FK `users` | **owner** (the nutritionist); required |
| `kind` | string | `"suggested"` (saved from a claim) \| `"custom"` (authored) |
| `body` | text | the note text — for suggested, the rendered claim prose (editable copy); for custom, free text |
| `condition_id` | FK `conditions`, nullable | the condition context it was saved under — **the key for §6 surfacing** |
| `study_id` | FK `scientific_studies`, nullable | source paper (suggested notes; custom may attach one) |
| `claim_id` | string, nullable | the source claim's id within that study's analysis (provenance; not a FK — claims are jsonb) |
| `section_id` / `paragraph_id` | string, nullable | reader deep-link anchor, captured at save so "open text" works from the saved note too |
| `quoted_text` | text, nullable | the verbatim evidence snapshot at save time (survives later re-analysis) |
| `details` | map | extensibility |
| timestamps | | |

- **Dedup:** partial unique index on `(user_id, study_id, claim_id)` where `claim_id IS NOT NULL`
  (saving the same suggestion twice is a no-op/toggle). Custom notes (`claim_id` null) are never
  deduped.
- **Reads:** `notes_for_user/1`, `notes_for_user_and_condition/2`, `saved_claim_ids/2`
  (`{user_id, study_id} → MapSet` so the card can show "Saved" state), `save_suggested/2`,
  `create_custom/2`, `delete/2`.
- **Privacy:** notes are **private to the owning nutritionist** (per-user). No sharing in v1.

## 5. Context / reuse

- Build the save/open affordances in `ResearchCondition` (the claim rendering already lives there:
  `visible_claims/1`, `endpoint/2`, `first_quote/1`). Point "Open in text" at `reader_url/3` with a
  **paragraph** anchor (new `#par-` variant alongside the existing `#sec-` one).
- The reader already resolves anchors + highlights — no reader-side work needed for Phase 1 beyond
  the per-note Save (Phase 2).
- Follow the `user_recipes` convention for the join/ownership; follow the existing
  nutritionist-gated route + `on_mount` for the "My notes" page.

## 6. Surfacing — **OPEN (evaluate later)**

The user wants saved notes shown back "at different times… for example when a client of his has this
condition." Two things to resolve before building this:

1. **Prerequisite — there is no structured `client ↔ Health.Condition` link today.**
   `ProfessionalClient` / `ClientIntake` record conditions only as **free text** (`hereditary_conditions`
   and friends in `details`), not as `Health.Condition` FKs. Surfacing "notes for this client's
   condition" needs a structured association first (e.g. a `condition_id` / join on
   `ProfessionalClient`, or resolving the intake's free-text conditions to `Health.Condition` via the
   existing `Health.ConditionResolver`). **Decide this first.**
2. **Where it appears** — candidates, to be chosen with the user:
   - the **client detail page** (`NutritionistLive.ClientDetail`) — a "Relevant research notes" panel
     keyed on the client's condition(s);
   - the **consultation-note composer** (`ConsultationNote`) — suggested notes offered as the
     nutritionist writes up a visit;
   - the standalone **"My notes"** page (§3c), always available regardless of client.
   The standalone page (Phase 2) is the safe, client-independent first home; client-surfacing is a
   later phase gated on #1.

> **YMYL / scope caution** (from `CLAUDE.md` Health context): condition-specific content stays inside
> the nutritionist-gated panel; do not surface notes to consumers / anonymous users.

## 7. Phasing

- **Phase 1 — rename + deep-link (presentational, no persistence). ✅ SHIPPED 2026-10-27.** The
  per-card `<details>` is relabelled **"Suggested notes (N)"** / "Hide suggested notes"
  (`show_findings_label/1` in `ResearchCondition`); each note's former PubMed "source" link is now
  **"Open in text"** → the reader at the claim's first `evidence[].paragraph_id`
  (`#par-…` via `claim_target/3` + `reader_paragraph_url/3`), falling back to a PubMed "source" link
  when the paper has no full text or the claim carries no paragraph anchor. No schema; the reader
  already resolved `#par-` anchors. Tests in `research_test.exs`.
- **Phase 2 — persistence. ✅ SHIPPED 2026-10-27.** `research_notes` table (migration
  `create_research_notes`, partial-unique `(user_id, study_id, claim_id) WHERE claim_id IS NOT NULL`)
  → `Mehungry.Professionals.ResearchNote` + context `Mehungry.Professionals.ResearchNotes`
  (`save_suggested/2` idempotent, `delete_suggested/3`, `create_custom/2`, `delete_note/2`,
  `list_for_user/1`, `list_for_user_and_condition/2`, `saved_claim_keys/2`). In `ResearchCondition`:
  a per-claim **Save** bookmark toggle (snapshots body/section/paragraph/quote server-side from the
  in-memory groups — never trusting client input; "Saved" state from `saved_claim_keys/2`) and a
  per-paper **"Write your own note"** composer (single-at-a-time, `:composing_study_id`). New
  standalone **"My notes"** page `NutritionistLive.MyResearchNotes` at `/nutritionist/research/notes`
  (route precedes `/research/:condition_id`), grouped by condition, each note deep-linking back to
  the reader (PubMed fallback) + delete. Linked from the search landing + condition headers. Tests:
  `professionals/research_notes_test.exs` + `research_test.exs`. Notes are private per user.
  **Follow-up (same day):** the reader (`ResearchPaper`) also gained the §3b floating notes widget
  (Save suggested notes + select-a-passage → sub-text custom notes via the `NoteSelection` hook);
  the claim-snapshot logic is shared across both surfaces via
  `ResearchNotes.suggested_attrs_from_claim/3`.
- **Phase 3 — client surfacing.** Resolve §6.1 (structured client↔condition link), then surface a
  client's condition notes in the chosen place (§6.2).

## 8. Open questions
- Editable suggested notes? (Proposed: Save copies the claim prose into `body`, editable thereafter.)
- Do custom notes attach to a **client** directly (bridging toward `ConsultationNote`), or only to a
  condition/study? (Proposed: condition/study in Phase 2; client in Phase 3.)
- Should hidden-by-curation claims (`wrong`/`ignore`) remain unsavable? (Proposed: yes — keep the
  existing `visible_claims/1` gate.)
- Naming: "Suggested notes" for the generated ones vs "My notes" for the saved collection — confirm
  the copy with the user.

## 9. Files a future session will touch
- `apps/mehungry_web/.../nutritionist_live/research_condition.ex` (+ heex) — relabel, Save/open
  affordances, write-your-own box.
- `apps/mehungry/lib/mehungry/professionals/research_note.ex` + `research_notes.ex` (new) and a
  migration `create_research_notes`.
- `apps/mehungry_web/.../nutritionist_live/` — new "My notes" LiveView + route (Phase 2).
- `docs/features/professionals/research_search.md` — cross-link; this doc owns the feature.
