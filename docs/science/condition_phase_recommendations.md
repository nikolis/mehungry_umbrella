# Phase-aware condition recommendations (disease-state pipeline)

**Status:** built 2026-09-23.

## The problem this solves

`Mehungry.Health` advice is keyed on `condition → compound|nutrient → avoid|encourage`
with **no notion of disease state**. For *Ulcerative Colitis* that flat food list is a
reasonable **remission** diet but can be harmful during an **active flare** (where
low-residue / low-fiber / low-FODMAP is indicated — the opposite of the remission
advice). Same for diverticulitis (acute vs prevention), gout (acute vs chronic),
pancreatitis, CKD stages.

The existing literature engine (`Health.RecommendationCandidates`) can't fix this: it
reads PubTator `chemical↔disease` **relations**, which are document-level and
**state-blind**. Phase lives only in the study **prose**, so this is a *separate*
pipeline whose extractor reads text, not relations — and it stays **decoupled** from
the general advice engines (its output is surfaced only on the condition page's phase
selector, never in `/foods`, badges, or blueprint auto-suggest — that "combine" step is
deliberate follow-on work).

## Flow

```
 (A) condition_states                seeded per condition (UC → Active Flare, Remission); admin-editable
        │
 (B) Condition.name × dietary/phase terms
        └─▶ ConditionCrawlWorker ──▶ scientific_studies (dedup by PMID)
                 │ ledger (condition_id, term)     └─(C) study_conditions  ── "Research on this condition"
                 ▼
 (D) mehungry_extractor (offline Python — not deployed)
        GET  /api/local_ai/condition_pending   → {study_id, pmid, condition, states}
        fetch PMC/PubMed text · optional scispaCy NER · LLM (Anthropic) direction+phase
        POST /api/local_ai/condition_recommendation_candidates
                 │ server ledgers (study_id, condition_id) → terminates
                 ▼
             condition_recommendation_candidates   (state-tagged, review-gated, never auto-promoted)
                 │  admin confirms direction+severity+STATE at /professional/health
                 ▼
 (E) condition_state_recommendations   (DECOUPLED from compound_recommendations)
                 └─▶ condition page phase selector (Active Flare | Remission | General)
```

## A — `condition_states`

A first-class per-condition phase registry (`Mehungry.Health.ConditionState`,
`health/condition_state.ex`). `condition_state_id = nil` on any recommendation/candidate
means **general / all-phase**. Most conditions have zero states and behave as before.
Seeded from `priv/repo/seeds/data/health_conditions.json` (optional `states: [...]` per
condition) by `Health.ConditionSeeder` (UC/Crohn's/Diverticulitis/Pancreatitis/Gout/CKD
ship with states). Context API: `Health.{list_states_for_condition, get_default_state,
upsert_state, delete_state}/1`.

## B — reverse (condition-seeded) crawl

`Literature.crawl_condition/1` (`literature/entrez.ex`) mirrors the species crawl,
seeding `condition.name × @dietary_phase_keywords`
(`diet dietary nutrition food fiber FODMAP remission flare exacerbation`) and reusing
the same cached esearch/efetch + rate-limit layer. Ledger `condition_crawl_attempts`
(`(condition_id, search_term)`), runs `condition_crawl_runs` +
`Literature.ConditionCrawlRuns` (topic `"condition_crawl_runs"`), worker
`ObanWorkers.ConditionCrawlWorker` (self-re-enqueueing `:imports` chain + poison-pill
guard), registered in `Science.PipelineWatchdog`/`RunReconciler`.

**Scope:** the crawl targets **only conditions that have ≥1 `condition_state`**
(`Literature.list_uncrawled_conditions/1`) — focusing NCBI volume where phase matters;
add states to a condition to include it. Triggered from `/professional/science`
("Run condition crawl").

## C — `study_conditions`

`Literature.StudyCondition` (`study_conditions`, unique
`(study_id, condition_id, search_term)`) — the condition analogue of `study_ingredients`.
`Literature.link_study_condition/1` + `list_studies_for_condition/1`. Powers the
"Research on this condition" section on the public condition page.

## D — extraction (offline Python + REST)

The extractor is a standalone, **non-deployed** Python project at `mehungry_extractor/`
(its own `pyproject.toml`; `anthropic`/`scispacy` never enter the release). It owns the
whole chain — fetch **and** LLM reasoning — because phase judgment is generative and
PubTator/extractive-QA can't do it. See `mehungry_extractor/README.md`.

Server side (`scope "/api/local_ai"`, bearer-guarded by `RequireLocalAiToken`):

- `GET /condition_pending` → `Api.LocalAi.ConditionPendingController`: `(study, condition)`
  pairs from `study_conditions` with **no** `condition_rec_extraction_attempts` row,
  each carrying the condition's states.
- `POST /condition_recommendation_candidates` → `Api.LocalAi.ConditionRecCandidatesController`:
  ledgers the attempt (so the pair leaves the pending set — termination) and upserts each
  finding via `Health.ConditionRecCandidates.upsert_candidate/1`, which resolves
  `raw_term → compound` (`Food.get_compound_by_name`, existing only — never mutates the
  registry) or `nutrient` (`NutrientNameNormalizer`) or leaves it a `food_pattern`, and
  the `condition_state_slug → ConditionState`. Idempotent on a computed `dedup_key`.

`condition_recommendation_candidates` + `..._candidate_studies` (additive provenance) +
`condition_rec_extraction_attempts` (termination ledger). **Never auto-promoted.**

## E — decoupled store + UI

`condition_state_recommendations` (`Health.ConditionStateRecommendation`) is a **separate**
advice store from `compound_recommendations` (so phase advice can't leak into the shared
read seams before the "combine" step). Target = compound | nutrient name | free-text
`raw_food_term`; `condition_state_id = nil` is general. Frozen provenance
`condition_state_recommendation_studies` (copied once at promotion).

- **Promotion:** `Health.ConditionRecCandidates.promote_candidate/2` — admin confirms
  `recommendation` + `severity` + `condition_state_id`, writes a
  `condition_state_recommendation` (`source: "literature"`), freezes the candidate's
  studies, marks the candidate `promoted`. Review UI at `/professional/health`
  ("Review phase-aware candidates").
- **Read seam:** `Health.state_recommendations_for_condition(condition_id, state_id \\ nil,
  language \\ nil)` — the state's rows **plus** the general (`nil`) rows; cached
  (`:health_cache`, state in the key).
- **Public:** condition page (`condition_detail_live/index.ex`) gets a phase selector
  (`select_state` event), an "Advice by disease phase" section, and a "Research on this
  condition" list. The existing general reads and every other surface are **untouched**.

## Files

New Elixir: `health/condition_state.ex`, `health/condition_state_recommendation.ex`,
`health/condition_state_recommendation_study.ex`,
`health/condition_recommendation_candidate.ex`, `..._candidate_study.ex`,
`health/condition_rec_extraction_attempt.ex`, `health/condition_rec_candidates.ex`,
`literature/study_condition.ex`, `literature/condition_crawl_attempt.ex`,
`literature/condition_crawl_run.ex`, `literature/condition_crawl_runs.ex`,
`oban_workers/condition_crawl_worker.ex`, migrations `20260924000001`–`…000005`.
New web: `controllers/api/local_ai/condition_pending_controller.ex`,
`…/condition_rec_candidates_controller.ex`. New Python: `mehungry_extractor/`.

## Testing

```bash
mix test apps/mehungry/test/mehungry/health/condition_rec_candidates_test.exs \
         apps/mehungry/test/mehungry/literature/condition_crawl_test.exs \
         apps/mehungry_web/test/mehungry_web/controllers/api/local_ai_condition_rec_test.exs
cd mehungry_extractor && pytest        # offline model/JATS tests
```

## Out of scope / follow-ons

- Unioning `condition_state_recommendations` into the shared read surfaces (`/foods`,
  `flags_for_recipes/ingredients`, blueprint) + conflict reconciliation — the "combine" step.
- Admin CRUD for `condition_states` (seeded + hand-authoring today).
- Migrating measurement/GI extraction into the Python extractor (one extraction toolchain).
