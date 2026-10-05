# Plan: IBD as parent of UC — UC-specific crawl + inherited IBD suggestions

## Context

On `/professional/health`, the Ulcerative Colitis (UC) bucket is dominated by
**Inflammatory Bowel Disease (IBD)**-level papers. Investigation of the dev DB found:

- Only UC (137 papers) and IBS (129) have any crawled papers; **UC ∩ IBS = 4**, so
  they're separate corpora (not the same IBD papers double-counted).
- **No "Inflammatory Bowel Disease" condition exists** in the registry — so the
  IBD-general papers UC pulls have nowhere else to live and can only attach to UC.
- The crawl (`Entrez.search_terms_for_condition/1`) queries PubMed with a bare
  free-text string `"<name> <keyword>"` (e.g. `"Ulcerative Colitis diet"`), with
  **no field qualifiers and no relevance gate** — every returned PMID is linked.
  PubMed maps "Ulcerative Colitis" toward its IBD parent, and the UC-diet corpus is
  largely IBD-framed, so the UC bucket fills with IBD-general papers.

Medically, UC ⊂ IBD, so IBD-level dietary evidence is a reasonable proxy for UC —
but it should be **clearly labelled as IBD-general, not silently treated as
UC-specific**. Chosen model (user): make UC's crawl UC-specific, introduce an **IBD
parent** condition to hold the shared evidence, and **surface IBD suggestions under
UC (and Crohn's) with an obvious "IBD-general" label**.

## Part A — Condition hierarchy (self-referential parent)

1. **Migration** (`apps/mehungry/priv/repo/migrations/`): add
   `parent_condition_id` to `conditions` — `references(:conditions, on_delete:
   :nilify_all)`, plus an index.
2. **Schema** `apps/mehungry/lib/mehungry/health/condition.ex`: add
   `belongs_to :parent, __MODULE__, foreign_key: :parent_condition_id` and
   `has_many :children, __MODULE__, foreign_key: :parent_condition_id`; cast
   `:parent_condition_id` in `changeset/2` + `foreign_key_constraint`.
3. **Seed IBD + links.** IBD is absent from
   `priv/repo/seeds/data/health_conditions.json` — add an **"Inflammatory Bowel
   Disease"** entry (category `gastrointestinal`, synonyms `["IBD"]`), and add an
   optional `"parent"` key to the **Crohn's Disease** and **Ulcerative Colitis**
   entries (`"parent": "Inflammatory Bowel Disease"`).
4. **`ConditionSeeder`** (`apps/mehungry/lib/mehungry/health/condition_seeder.ex`):
   after upserting all rows, resolve each row's `"parent"` name → id and set
   `parent_condition_id` (second pass, so order-independent). Keep idempotent. The
   admin "Seed registry" button already calls `ConditionSeeder.seed/0`, so this is
   re-runnable from the UI.

## Part B — UC-specific crawl (name-anchored retrieval)

Change **`Entrez.search_terms_for_condition/1`**
(`apps/mehungry/lib/mehungry/literature/entrez.ex:185`) so a paper must actually
**name the condition**, instead of the bare `"<name> <keyword>"`:

- Build `"\"#{condition.name}\"[tiab] AND #{keyword}"` (phrase in Title/Abstract).
  `Entrez.Client.esearch/2` passes `term` straight to PubMed (URI-encoded), so
  field tags work as-is.
- This cleanly separates buckets: a paper that names "ulcerative colitis" lands in
  UC; a Crohn's/IBD-only paper that never names UC drops from UC and (once IBD is
  crawled) lands in **IBD** via `"inflammatory bowel disease"[tiab]`.
- Applied generically to all conditions (sound precision improvement). `[tiab]` is
  robust for conditions without a MeSH id (IBS/Crohn's have none); UC's MeSH
  (`D003093`) isn't required for this approach.

**Migration note (no code, call out in plan):** term strings change, so
`condition_crawl_attempts` (ledgered by `search_term`) won't match and conditions
**re-crawl** with the tighter query on next "Search papers" — intended. Existing
broad UC↔paper links in `study_conditions` **remain** (not auto-deleted); the admin
can set those claims to Wrong/Ignore, or re-crawl IBD to collect the general set.
No destructive cleanup in this plan.

## Part C — Inherited IBD suggestions under UC (clearly labelled)

Surface a condition's **parent's** suggestions beneath its own, in the Suggestions
tab, visibly marked as inherited/general.

- **`health_conditions.ex` `load_condition_detail/2`**: if the condition has a
  `parent_condition_id`, also compute `ClaimRules.rules_for_condition(parent_id)`
  and store it keyed by cid alongside the parent's name (new assign, e.g.
  `:condition_parent_rules` → `%{cid => %{name: parent_name, rules: [...]}}`).
  Needs a parent lookup — preload `:parent` via `Health.get_condition/1` or a small
  `Health.get_parent_condition/1` helper.
- **Suggestions tab** (`health_conditions.html.heex`): after the condition's own
  `food_related_rules`, render a separate, clearly-labelled block —
  *"Inherited from Inflammatory Bowel Disease — general IBD evidence, review before
  applying to this condition"* — listing the parent's `food_related_rules` (reuse
  the same row markup + `food_related_sources/1` + disease-state badges). **Read-only
  / informational** (matches the current non-destructive suggestions model); the
  admin adds a UC recommendation by hand via the existing "Add recommendation" form
  if they agree. The **Refresh** button re-evaluates both own + inherited.

## Critical files

- `apps/mehungry/lib/mehungry/health/condition.ex` (schema + changeset)
- `apps/mehungry/lib/mehungry/health/condition_seeder.ex` (parent resolution)
- `apps/mehungry/priv/repo/seeds/data/health_conditions.json` (IBD entry + parent keys)
- `apps/mehungry/priv/repo/migrations/*_add_parent_condition_id.exs` (new)
- `apps/mehungry/lib/mehungry/literature/entrez.ex` (`search_terms_for_condition/1`)
- `apps/mehungry_web/lib/mehungry_web/live/professional_live/health_conditions.ex` + `.html.heex`
- Reuse: `Mehungry.Health.ClaimRules.rules_for_condition/1`, the LiveView's
  `food_related_rules/1` / `food_related_sources/1`, `Entrez.Client.esearch/2`.

## Tests

- `condition` parent round-trip + `ConditionSeeder` sets UC/Crohn's → IBD parent
  (extend `condition_seeder`/health tests).
- `Entrez.search_terms_for_condition/1` emits name-anchored `[tiab]` queries
  (unit test the produced term strings; no network).
- LiveView (`health_conditions_test.exs`): seed IBD parent + UC child, store an
  IBD analysis with a food_related claim, expand UC → Suggestions tab shows the
  inherited block labelled with the parent name and the IBD suggestion; UC's own
  suggestions stay in their own section.

## Verification

1. `mix ecto.migrate`; run `ConditionSeeder.seed/0` (or the admin "Seed registry"
   button) → IBD condition exists, UC/Crohn's `parent_condition_id` set.
2. `/professional/health`: "Search papers" on **IBD** → IBD-general papers; on
   **UC** → now UC-named papers only (spot-check a few PMIDs actually name UC).
3. Analyze + mark some IBD claims *Food related* → open **UC** → Suggestions tab
   shows them under the "Inherited from Inflammatory Bowel Disease" block; Refresh
   re-evaluates.
4. `mix test` the three files above.
