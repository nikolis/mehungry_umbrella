# Compound Candidates — the curation step

A **two-stage candidate → curated pipeline** that turns accumulated evidence into
**species-keyed** `SpeciesCompoundRelationship` facts. Candidates and facts are keyed on
`FoundementalFoodSpecies` (one suggestion/fact per species, not per USDA ingredient
variant), and every candidate cites the **reference studies** it was extracted from
(`SpeciesCompoundCandidateStudy`). It is the "separate human-curation step" the fact
layers explicitly defer to: PubTator mentions and literature co-occurrence must
**never** write a relationship directly (`docs/science/pubtator.md` §1, `docs/science/food_compounds.md`
§4). This layer reads that evidence, proposes **candidates**, scores them, and promotes
the strong ones — automatically or by admin review — into the curated facts table.

> *Apricot / Flavonoids*: 5 co-occurrence studies (rolled up from the species' USDA
> ingredients) → candidate scored **1.0 (strong)**, citing those 5 PMIDs →
> auto-promoted to `SpeciesCompoundRelationship(contains, source: literature)`.

```
 PubTator mentions ─┐
 measurements ──────┤─ derive + score ─▶ species_compound_candidates ─┬─ auto (score≥thr) ─▶ SpeciesCompoundRelationship
 manual import ─────┘  (worker + run)    (pending|promoted|rejected)      └─ admin Promote/Reject ┘   (curated "facts")
                                                                                                            │
                                          Food.list_positive_compounds_for_species/1 ◀───────────────────┘
                                                                    │
                                          Literature.search_terms_for_species  (targeted crawl terms — the feedback loop)
```

The candidate table is deliberately **separate** from `species_compound_relationships`
so the facts table stays curated-only — unreviewed proposals never masquerade as facts.
This mirrors the `IngredientTaxonomyNode` (candidate) → confirmed pattern.

---

## 1. Why this exists

`Food.Compounds` stores qualitative facts, `Food.CompoundMeasurements` stores
quantitative ones, and `Literature`/`PubTator` discover evidence — but nothing
connected the evidence to a *curated* ingredient↔compound fact. As a result the
literature crawler only ever used generic keyword terms
(`Literature.Entrez.@generic_keywords`), because `list_positive_compounds_for_species/1`
returned nothing.

This layer closes the loop:

1. **Derive** candidates from evidence and **score** them.
2. **Promote** strong ones (≥ threshold) automatically, queue the rest for review.
3. Promoted relationships become **targeted crawl terms**, improving recall on the
   next crawl — a feedback loop that needs no hand-curated seed list, and no separate
   PubChem seeding phase (the registry keeps populating lazily via PubTator).

**Boundaries honored:**

- Evidence sources never write relationships directly — only this curation step does.
- The facts table is unchanged; candidates live in their own table.
- Auto-promotion is a **documented, config-tunable threshold**, not a hidden rule.

---

## 2. Data model

`priv/repo/migrations/20260807120000_create_species_compound_facts.exs` creates the
species-keyed tables: `species_compound_relationships` (curated facts),
`species_compound_candidates` (proposals), and `species_compound_candidate_studies`
(the reference-study provenance join — one row per `(candidate, study)`).

### `species_compound_candidates` — staged proposals
One row per `(foundemental_species_id, compound_id, relationship_type)` (natural key,
upsert on re-derivation). Its reference studies live in
`species_compound_candidate_studies` (refreshed each derivation from the current
co-occurrence set) and are exposed via `list_candidate_studies/1` / the `:studies` preload.

| Column | Meaning |
|---|---|
| `foundemental_species_id` / `compound_id` | The pair (`on_delete: delete_all`). |
| `relationship_type` | What it would promote to — positive-presence only (`contains`). |
| `status` | `pending → promoted \| rejected`. |
| `evidence_score` | 0.0–1.0 blended score (see §3). |
| `evidence_level` | `strong \| moderate \| limited \| insufficient`. |
| `study_count` | Distinct co-occurrence studies (literature). |
| `measurement_study_count` | Distinct measurement-backed studies. |
| `sources` | `text[]` of contributing sources: `pubtator \| measurement \| manual`. |
| `evidence` | jsonb audit breakdown (component sub-scores + raw counts). |
| `promoted_relationship_id` | FK → the curated fact this promoted into (`nilify_all`). |

### `candidate_derivation_runs` — batch progress tracker
Mirrors `literature_crawl_runs`: `status`, `processed`/`total`,
`promoted_count`, `error`, `started_at`/`completed_at`. Drives a live progress bar.

---

## 3. Scoring (`Food.CompoundCandidates.score_candidate/2`)

Two orthogonal evidence signals, blended with **noisy-OR** so strong evidence from
*either* source reaches "strong", and both compound:

- **Literature** — `min(cooccurrence_studies / @cooccurrence_saturation, 1.0)`
  (`@cooccurrence_saturation = 5`). Co-occurrence = a resolved chemical mentioned in a
  paper linked to any ingredient of the species (`Literature.species_cooccurrence_study_count/2`,
  joining `StudyEntityMention.compound_id` → `StudyIngredient.ingredient_id` →
  `FoundementalFood.foundemental_species_id` via `study_id`).
- **Measurement** — `Food.EvidenceAggregation.summarize_species/2`'s `evidence_score`
  (aggregating the species' ingredient measurements), or `0.0` when there are none.
- **Blend** — `evidence_score = 1 − (1 − literature) · (1 − measurement)`.

`evidence_level` uses the same cutoffs as `EvidenceAggregation` (`:strong ≥0.75`,
`:moderate ≥0.5`, `:limited ≥0.25`, else `:insufficient`). The component breakdown is
stored in `evidence` so the rating is auditable.

---

## 4. Promotion — auto + review

- **Auto**: after deriving, a `pending` candidate scoring ≥
  `candidate_promotion_threshold` (config, default **0.75**) is promoted immediately —
  mirrors `TaxonomyClassificationWorker`'s auto-confirm, nil-guarded — **but only after
  it clears the two credibility filters below**.
- **Review**: everything else waits in `list_pending_candidates/1` (strongest first).
  An admin **Promotes** or **Rejects** it at `/professional/compound-candidates`.

### Why the filters — document co-occurrence ≠ containment

The literature signal is document-level co-occurrence (`species_cooccurrence_study_count/2`):
a resolved chemical mentioned *anywhere in a paper* linked to the species. That is a weak
proxy for "the food contains it" — 4 such studies score exactly 0.80 and, unfiltered,
auto-promoted false positives like *Acerola contains Ethanol* (extraction solvent),
*Apricot contains reactive oxygen species* (the scavenged target), *Alfalfa contains heavy
metal* (contamination). Two filters gate auto-promotion (manual admin promotion bypasses
both — a human decision):

1. **Curatable `dietary_relevance` on `Compound`** (`dietary | non_dietary | pending`,
   default `pending`) — the scalable successor of the exact-name blocklist. `non_dietary`
   compounds (solvents, contaminants, assay reagents, non-specific class terms) are
   excluded from `evidence_pairs/0`, purged on each derive (`purge_non_dietary/0`), and
   filtered out of `Health` advice reads. Set via `Food.set_dietary_relevance/2`, or the
   one-click **"Non-dietary"** button on a candidate row.
2. **LLM plausibility gate** (`Food.CompoundPlausibility`, behind the
   `:compound_plausibility_judge` seam) — the automated "reality check". For a ≥-threshold
   candidate whose compound is not already curated `dietary`, a cheap Haiku call judges
   whether the compound is plausibly an *intrinsic dietary constituent* of the species
   (vs. a solvent / contaminant / reagent / measured target), fed the co-occurring study
   titles/abstracts. Only `:plausible` promotes; `:implausible`/`:uncertain`/any judge
   error/no API key **hold the candidate `pending`** (fail-safe — never silently
   rejected). The verdict + reason are cached on the candidate
   (`plausibility_verdict`/`plausibility_reason`, reused on re-derivation) and shown in
   the review queue. The judge is wrapped so an AI fault can **never** bubble into the
   derivation worker and poison-pill the `:imports` chain. A compound curated `dietary`
   skips the LLM (trusted fast-path).

Promotion writes the curated fact via `Food.SpeciesCompounds.upsert_species_relationship/1`
(`source: "literature"` for derived, `"manual"` for manual-origin, `confidence =
evidence_score`) and flips the candidate to `promoted`, linking `promoted_relationship_id`.
Idempotent. Re-derivation **never** touches a `promoted`/`rejected` status — only the
evidence fields refresh.

Promotion also **freezes the fact's PubMed provenance**: it copies the candidate's
reference studies into `species_compound_relationship_studies` (`relationship_id` →
`study_id`), the mirror of `species_compound_candidate_studies` but **written once and
never refreshed** — so the curated fact keeps citing exactly the papers it was promoted
from, even as re-derivation rewrites the candidate's study set. Exposed as the
relationship's `:studies` `has_many :through`. (The advice-layer analogue is
`compound_recommendation_studies` — see `health_recommendations.md` §2.)

Config:

| Key | Default | Purpose |
|---|---|---|
| `:candidate_promotion_threshold` | `0.75` | Score at/above which a candidate is *eligible* to auto-promote (still subject to the two filters). |
| `:non_dietary_compounds` | `DPPH ABTS … Ethanol "Reactive Oxygen Species" "Heavy Metal" …` | **Seed list only** for the one-time migration backfill of `Compound.dietary_relevance = "non_dietary"`. The runtime source of truth is now the per-compound attribute, not this list. |
| `:compound_plausibility_judge` | `Food.CompoundPlausibility` | The LLM reality-check module; stubbed in tests (`config/test.exs` → `CompoundPlausibilityStub`, default `:plausible`). |

**Reviewing/correcting the curated output.** `/professional/compound-candidates` shows, below the
pending queue, a **Curated facts** list of the promoted `SpeciesCompoundRelationship` rows with an
**Undo** action (`unpromote_relationship/1` — deletes the fact and marks its candidate `rejected` so
re-derivation won't re-promote it) and a **Purge non-dietary** button. Each pending candidate row
shows the plausibility verdict/reason and a **"Non-dietary"** button that flags the compound and
purges its facts globally. Reached from the Science Pipeline's derivation stage via
"Review candidates & facts →".

### Auditing already-promoted facts

The gate only guards *new* auto-promotions; facts promoted before the gate existed were
never judged. The **"Audit facts"** button (`enqueue_fact_audit/0` →
`CompoundFactAuditWorker`, `:imports`) re-runs the same judge over every promoted
`literature` fact on a `pending`-relevance compound whose backing candidate has no
`plausibility_verdict`. The worker self-re-enqueues in small batches (LLM calls) and
terminates on a tick that makes no progress — either nothing is left, or the judge is
unavailable and every call errored, in which case un-audited facts simply remain for a
later re-run (a transient AI outage can't wedge it). Implausible facts are recorded as
`implausible` on the candidate and surface in a **"Flagged facts — needs review"** list at
the top of `/professional/compound-candidates`, each with the reason and **Undo** /
**Non-dietary** actions. The audit **only flags — it never deletes a fact** (a human
decides), the mirror of the gate's "never silently reject".

---

## 5. The pipeline (Oban run with progress)

`Mehungry.ObanWorkers.CompoundCandidateDerivationWorker` (`:imports` queue) mirrors
`LiteratureCrawlWorker`: a single job threads `run_id` + `offset` through a
self-re-enqueueing chain, deriving a window of `evidence_pairs/0` each tick,
auto-promoting, and refreshing the run — until the offset runs past the pairs, then
marking the run `completed`. Derivation is pure DB work (no external API), so an empty
batch means done and re-derivation is idempotent.

```elixir
{:ok, run} = Mehungry.Food.enqueue_candidate_derivation()
Mehungry.Food.candidate_derivation_progress()  #=> %{processed: _, total: _}
```

Every transition broadcasts `{:candidate_derivation_run, run}` on `Mehungry.PubSub`
topic `"candidate_derivation_runs"` for the live progress bar.

---

## 6. The feedback loop

`Food.list_positive_compounds_for_species/1` returns every relationship except
`absent` (deduped) across the species' curated ingredients — this is what
`Literature.Entrez.search_terms_for_species/1` now reads to build compound-targeted
crawl terms. So each promoted candidate becomes a targeted search term on the next
crawl. (The `!= "absent"` filter guards the loop: a negative fact must never leak in
as a search term.)

---

## 7. Module map

| Module | File | Role |
|---|---|---|
| `Food.CompoundCandidates` | `food/compound_candidates.ex` | Derivation, scoring, promotion/review (incl. the plausibility gate), queries. |
| `Food.CompoundPlausibility` | `food/compound_plausibility.ex` | The LLM reality-check judge (behind `CompoundPlausibilityBehaviour`). |
| `Food.IngredientCompoundCandidate` | `food/schemas/ingredient_compound_candidate.ex` | Staged-proposal schema. |
| `Food.CandidateDerivationRuns` | `food/candidate_derivation_runs.ex` | Run lifecycle + PubSub progress. |
| `Food.CandidateDerivationRun` | `food/schemas/candidate_derivation_run.ex` | Run schema. |
| `ObanWorkers.CompoundCandidateDerivationWorker` | `oban_workers/compound_candidate_derivation_worker.ex` | Batch-chain derivation worker. |
| `ObanWorkers.CompoundFactAuditWorker` | `oban_workers/compound_fact_audit_worker.ex` | Batch-chain re-audit of already-promoted literature facts (flags implausible ones). |
| `Literature.compound_ingredient_cooccurrences/0` · `cooccurrence_study_count/2` | `literature.ex` | The co-occurrence evidence join. |
| `MehungryWeb.ProfessionalLive.CompoundCandidates` | `mehungry_web/.../professional_live/compound_candidates.ex` | Admin derive + review UI. |

All public context functions are exposed via the `Mehungry.Food` facade.

---

## 8. Testing

```bash
mix test apps/mehungry/test/mehungry/food/compound_candidates_test.exs \
         apps/mehungry/test/mehungry/oban_workers/compound_candidate_derivation_worker_test.exs \
         apps/mehungry_web/test/mehungry_web/live/professional_live/compound_candidates_test.exs
```

- **Context** — co-occurrence counting (and the not-linked exclusion), noisy-OR scoring
  (literature-only saturation, measurement-only, both compounding), auto-promotion at/above
  threshold (writes the fact) vs. below (stays pending), re-derivation preserving a decided
  status, promote idempotency, reject, manual import, pending ordering, and the
  `list_positive_compounds_for_species` `absent` exclusion.
- **Worker** — batch derive + auto-promote count + progress + chaining, and run completion.
- **LiveView** — renders the queue, Promote/Reject write the fact / flip status and drop the
  row, Derive enqueues the worker + opens a run, a broadcast moves the bar, non-admin redirect.

---

## 9. Out of scope / follow-ons

- Positive-presence candidates only (`contains`); negative (`absent`) facts are not derived.
- No unit normalization or per-preparation nuance (inherited from the measurement/aggregation
  layers).
- Re-scoring a manual candidate that later gains literature/measurement evidence replaces its
  `sources`; the manual provenance marker is not unioned (manual-only pairs are never re-derived,
  since they are not in `evidence_pairs/0`).
