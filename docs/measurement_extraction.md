# Measurement extraction (local-AI service + REST)

Auto-extracts quantitative compound measurements (`compound = value unit`) from the
literature we crawl, as **review-gated candidates** (never facts). Composition numbers
live in full-text results/tables, so a paper's **PMC open-access full text** is fetched
and a **local Bumblebee extractive-QA model on EXLA** is run over it (with a rule-based
fallback).

Because that work is heavy and GPU/CPU-bound, it runs **off the deployed box** in a
separate, non-deployed umbrella app — `apps/mehungry_local_ai` — that talks to the
server only over REST. The deployed apps carry **no** Bumblebee/EXLA/Nx dependency.

## Split

```
LOCAL GPU BOX  (apps/mehungry_local_ai, not in the release)      PRODUCTION (mehungry_web)
──────────────────────────────────────────────────────         ─────────────────────────
mix local_ai.extract --limit N
  GET  /api/local_ai/pending   ───────────────────────────▶     list_unfetched_studies + compounds
       ← [{study_id, pmid, compounds:[{id,name,synonyms}]}]
  PMC.fetch(pmid)  (resolve PMCID → efetch db=pmc → JATS→text)
  POST /api/local_ai/full_text ───────────────────────────▶     upsert_full_text + record_pmc_attempt
  Extractor.findings(text, compounds)  (QA + rule fallback)
  POST /api/local_ai/candidates ──────────────────────────▶     fan out over species_ids_for_study,
       {candidates:[{study_id, compound_id, value, ...}]}        upsert_measurement_candidate
```

Division of labor: the local service is **pure NLP + HTTP** (no DB, no species
knowledge); the server does **domain association + persistence** (fans each finding
across the `FoundementalFoodSpecies` the study links to, and owns the tables + review UI).

## Local app (`apps/mehungry_local_ai`)

- `MehungryLocalAi.QA` — Bumblebee QA `Nx.Serving` (`distilbert-squad`, `compiler: EXLA`).
  Started by `MehungryLocalAi.Application`; `config :mehungry_local_ai, start_qa: false`
  disables it (tests → rule path only).
- `MehungryLocalAi.PMC` + `PMC.Client` + `PMC.Parser` — PMID→PMCID (idconv), `efetch
  db=pmc`, JATS→text. HTTP behind the `:pmc_http_adapter` seam (stubbed in tests); a
  fixed `Process.sleep` pace keeps under NCBI's courtesy limit.
- `MehungryLocalAi.Extractor` — `findings(text, compounds)` → `[%{compound_id, value,
  unit, preparation_method, analytical_method, score, raw_span, extraction_method}]`.
  QA-primary when the serving is loaded, else the regex rule finder.
- `MehungryLocalAi.Client` — HTTP client (`pending/2`, `post_full_text/1`,
  `post_candidates/1`) with `Authorization: Bearer`.
- `mix local_ai.extract [--limit N] [--offset M]` — boots the app (loads the model
  once), pulls pending work, fetches + extracts, posts back, prints a summary.

Config (env, read in `config/runtime.exs`): `LOCAL_AI_SERVER_URL`, `LOCAL_AI_API_TOKEN`.

## Server (`apps/mehungry_web`)

Token-guarded REST API (`MehungryWeb.Plugs.RequireLocalAiToken` — shared-secret bearer,
constant-time compare against `:mehungry, :local_ai_api_token`; 401 mismatch / 500 if
unset), pipeline `:local_ai_api`, `scope "/api/local_ai"`:

- `GET  /pending`   → `PendingController` — `Literature.list_unfetched_studies/1` + each
  study's compounds (`Food.get_compounds_by_ids(Literature.compound_ids_for_study/1)`).
  A study leaves the set once a fetch attempt is ledgered → the local batch terminates.
- `POST /full_text` → `FullTextController` — `Literature.upsert_full_text/1` (when body)
  + `Literature.record_pmc_attempt/1` (always).
- `POST /candidates`→ `CandidatesController` — fan out over `Literature.species_ids_for_study/1`
  → `Food.upsert_measurement_candidate/1` (idempotent).

Review is unchanged: `/professional/compound-candidates` → **Accept** materializes a
`CompoundMeasurement` via `Food.record_measurement/1` against a representative curated
ingredient of the species; **Reject** drops it. `/professional/science` shows a
read-only "Full-text extraction" status (unfetched count + pending-candidate count).

## Tables

`study_full_texts`, `pmc_fetch_attempts`, `compound_measurement_candidates`
(migration `20260808120000_create_measurement_extraction.exs`). The old
`literature_extract_runs` / `literature_extract_settings` pipeline tables are gone —
extraction is no longer a server-side Oban pipeline.

## Deployment

`apps/mehungry_local_ai` is **not** in the release (`mix.exs` `releases:` lists only
`mehungry` + `mehungry_web`) and the `Dockerfile` never copies its `mix.*` and
`rm -rf`s the app before building, so Bumblebee/EXLA/XLA are never fetched or compiled
in production.

## Tests

`apps/mehungry_local_ai/test/` — `Extractor` (rule path) + `PMC` (stubbed HTTP).
`apps/mehungry_web/test/.../api/local_ai_test.exs` — the three endpoints + token 401.
`apps/mehungry/test/mehungry/food/compound_measurement_candidates_test.exs` — server-side
upsert + accept/reject.
