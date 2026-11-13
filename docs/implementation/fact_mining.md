# The Fact-Mining Pipeline — biomed-fact-miner → per-entity mined facts

> **Replaces the retired `Mehungry.CompoundPipeline` (species↔compound derivation), 2026-11-12.**
> Instead of deriving a noisy species↔compound graph from a frozen literature corpus, the app now
> asks an external **biomed-fact-miner** service for PMID-cited biomedical **facts** per entity and
> stores them verbatim-safe. The whole species↔compound graph (`species_compound_relationships`,
> candidates, derivation runs, the ①→④ admin page, the plausibility LLM gate) was **dropped**.

`Mehungry.FactMining` is the context. For each entity it builds a natural-language query, calls the
miner's `POST /mine`, and **replaces** that entity's stored facts (wipe-then-insert, so a re-run is
idempotent). Two entity surfaces share the machinery:

- **Species** (`SpeciesMinedFact`, table `species_mined_facts`) — an **entity-scope** query
  `"tell me all the facts about {name} ({scientific_name})"`. Surfaced on the public species detail
  page (`/foods/:slug` "Research findings") and the `/api/v1/species/:slug` detail (`research[]`).
  The species page renders the facts as a **verdict-led "evidence ledger"** (not a flat list): a
  header tally (`✓ verified · ✕ contradicted · unverified`), then facts grouped by verdict — the
  **Verified** claims lead (the readable payload), the disputed + unverified tail collapses behind one
  Alpine toggle ("Show N findings under review"). Within a group, facts rank **human-relevance**
  (`claim_type`: a `treatment_outcome`/`treatment_safety` outbeats a lab `mechanistic` claim) →
  verdict → **evidence strength** (`study_design` via the shared `Literature.ResearchType` pyramid;
  `rct` gets a highlighted chip). Each row carries a verdict-colour left rail + badge, an
  acronym-correct study-design chip (`SpeciesDetailLive.study_design_label/1` — fixes the
  `Phoenix.Naming.humanize("rct") => "Rct"` miscasing), the PMID link, and a per-fact **"Why?"** that
  expands the mined `reason`. The uniform-`very_low` `certainty` is intentionally **not** shown. All
  facts stay in the crawlable dead-render DOM — Alpine only toggles visibility, so SEO is unaffected.
- **Condition** (`ConditionMinedFact`, table `condition_mined_facts`) — a **relational** query
  `"give me all the food related facts about {condition}"`, feeding the nutritionist research surface
  (`research_for_condition/1`, `conditions_for_search/1`); each mined PMID is enriched into the
  `ScientificStudy` registry for publication-card metadata.

## The external service (biomed-fact-miner)

A FastAPI pipeline (sibling repo `/home/nikolis/git/biomed-fact-miner`). `POST /mine` returns a
`FactSheet.to_dict()`: `{query, scope_kind (entity|relational|out_of_scope), counts, facts[], trace[]}`.
Each `facts[]` element wraps a verdict (`label`, `certainty`, `reason`, `conflicting_pmid`,
`assessment`) around an inner fact (`fact_id`, `text`, `claim_type`, `pmid`, `quote`, `char_span`,
`study_design`, `source`, `pmcid`, `doi`, `pub_status`, `structured_effect`, `license`, `license_raw`).

`label ∈ verified | contradicted | unverified_quality | unverified_fulltext |
unverified_insufficient | unverified_verification` — **`verified` is the only "released" state**; every
other label is an honest reason a claim fell short. We store **all labels** and let the UI badge by
state.

**Licensing / quote safety.** We always call `?view=public`, so the API already redacts verbatim
`quote`s from non-`commercial_ok` sources. As defense-in-depth, `FactMining.map_fact_sheet/3` persists
the `quote` **only** when `license == "commercial_ok"` — we never store the `"[quote withheld — …]"`
placeholder. `text` + `pmid` + `license` are always stored.

The service is **synchronous and slow** (LLM + PubMed/PMC retrieval, internal ~3 req/s throttle), so
the client uses a generous timeout and the sweep runs single-concurrency.

## Client + config seam

`Mehungry.FactMining.Client` (behind `FactMining.ClientBehaviour`, `:fact_miner_client` seam —
stubbed in tests by `Mehungry.FactMining.ClientStub`). HTTPoison, modeled on `Mehungry.Extractor`.

**UI-managed connection.** The service URL and an optional **JWT/bearer token** are a singleton
`FactMining.Settings` row (table `fact_miner_settings`), editable on `/professional/health` (the
"Mine conditions" card → **Configure**). `FactMining.connection/0` returns `{base_url, auth_token}`,
preferring the saved row and falling back to the config/env below, then the built-in default — so an
admin can re-point the miner and set a token without a redeploy (mirrors `Extractor.Settings`). When
a token is present it is sent as `Authorization: Bearer <jwt>`.

| Config key | Default | Purpose |
|---|---|---|
| `:fact_miner_base_url` (`FACT_MINER_BASE_URL`) | `http://127.0.0.1:8811` | Service base URL fallback (deliberately distinct from the extractor's `:8000`). |
| `:fact_miner_auth_token` (`FACT_MINER_AUTH_TOKEN`) | `nil` | JWT/bearer token fallback, sent as `Authorization: Bearer …`. |
| `:fact_miner_timeout_ms` (`FACT_MINER_TIMEOUT_MS`) | `120_000` | `/mine` recv timeout (mining is slow). |
| `:fact_miner_client` | `FactMining.Client` | The test seam. |

- `connection/0` → `{base_url, auth_token}` (UI row → config/env → default; trailing slash trimmed).
- `mine/2` → `POST {base}/mine?format=json&view=public`, body `%{query, fetch_fulltext: true, max_records: 200}`, bearer header when a token is set.
- `reachable?/0` → short-timeout `GET {base}/health` (pre-flight before a sweep), bearer header when set.

## Species sweep — the admin pipeline (Oban-UI-connected)

`/professional/compound-pipeline` (`MehungryWeb.ProfessionalLive.FactMiningPipeline`, admin-gated;
route reused from the retired page). "Mine all species" fans out one job per species following
`docs/reference_architecture/oban_ui_connected_worker.md`:

```
Mine all species ─▶ SpeciesFactMiningRuns.mine_all_species/0
  preflight reachable? ─ create one `pending` species_fact_mining_runs row per species
  (Repo.insert_all) ─ Oban.insert_all one SpeciesFactMiningWorker job per species
                                   │
  :fact_mining queue (concurrency 1) ─ one job == one species
    SpeciesFactMiningWorker.perform ─▶ FactMining.mine_species/1 (wipe + insert)
                                   │        mark_processing → mark_completed | mark_failed
                                   ▼
  PubSub "species_fact_mining_runs" ─▶ LiveView streams per-species rows (O(1) patch),
    slim {:fact_mining_processing, batch, species} coalesced behind a ~400ms flush timer;
    full {:fact_mining_run, row} on terminal. Aggregate progress = counts over batch_id.
```

- `species_fact_mining_runs` — **one row per species per `batch_id`** (status `pending → processing →
  completed | failed`, `facts_total` / `verified_count` / `contradicted_count`, `error`). The LiveView
  streams these and derives batch progress by counting over `batch_id` (no separate aggregate table).
- Worker (`:fact_mining`, `max_attempts: 3`): a transient miner failure returns `{:error, _}` so Oban
  retries (wipe-then-insert is idempotent); on the **final** attempt the species is recorded `failed`
  so the batch still finalizes. `cancel_batch/1` cancels remaining jobs + marks unfinished rows failed.

`:fact_mining` is its own single-concurrency Oban queue (total concurrency 14, pool 18) so the slow,
self-throttled miner can't starve other work.

### Concurrency & backpressure — one miner call at a time, cluster-wide

The queue's `limit: 1` is only **per node**, and production runs **2 Fly machines**, so two `/mine`
requests could otherwise fire at once. Two layers keep it to exactly one:

- **Leader-gated queue (proactive).** `:fact_mining` starts **paused** on every node
  (`config/config.exs`). `Mehungry.FactMining.QueueLeader` — a small supervised poller, one per node —
  checks Oban leadership every ~20s and **resumes the queue only on the leader** (`local_only`),
  keeping it paused everywhere else. The leader's single slot then serializes mining naturally (jobs
  wait in `available`, no snooze churn). It reuses Oban's existing **Database** peer leadership lease
  (DB-based, so it works even though the Fly machines aren't Erlang-clustered); it is **not** started
  under the test config (`testing: :manual`). On a leadership change the new leader resumes within one
  tick, and any in-flight job on the old leader finishes or is rescued by `Lifeline` and re-run
  (mining is idempotent). This is why no DB lock is held across the call — a single `/mine` can take
  **up to ~10 min**, so pinning a pooled connection for its duration is unacceptable.
- **429 / `Retry-After` (reactive safety net).** The miner enforces its **own** concurrency limit and
  returns **HTTP 429** when saturated. `FactMining.Client.mine/2` maps that to
  `{:error, {:rate_limited, seconds}}` (parsed from the `Retry-After` header, defaulting to 30s,
  clamped ≥5s); both workers turn it into `{:snooze, seconds}` — rescheduling **without** burning a
  retry or marking the run failed. This covers any brief overlap during a leadership handoff.

## Condition sweep — the admin trigger on `/professional/health`

The condition branch mirrors the species sweep exactly, from a different admin surface. The **"Mine
conditions (fact-miner)"** card on `/professional/health` (`MehungryWeb.ProfessionalLive.HealthConditions`)
replaced the old extractor "Research ingestion" card:

```
Mine all conditions ─▶ ConditionFactMiningRuns.mine_all_conditions/0
  preflight reachable? ─ one `pending` condition_fact_mining_runs row per condition
  (Repo.insert_all) ─ Oban.insert_all one ConditionFactMiningWorker job per condition
                                   │
  :fact_mining queue (concurrency 1) ─ one job == one condition
    ConditionFactMiningWorker.perform ─▶ FactMining.mine_condition/1 (wipe + insert + enrich PMIDs)
                                   │        mark_processing → mark_completed | mark_failed
                                   ▼
  PubSub "condition_fact_mining_runs" ─▶ the LiveView refreshes aggregate counts
    (counts_for_batch) on every transition; reloads the page once the batch drains.
```

`mine_condition/1` additionally **enriches** each distinct `pmid` via `Literature.fetch_and_upsert_study/1`
(cached — the stored row is returned with no network when present) so publication cards carry real
title/journal/authors/year + MEDLINE badge. The miner returns only PMID/PMCID/DOI.

The nutritionist then reads it offline: `FactMining.research_for_condition/1` groups the stored facts by
`pmid` into **publications**, tagged **presentable** when `license == "commercial_ok"` (shown with their
verbatim quotes, grouped by research type) vs a flat **free-claims** section (distilled wording + a
source link, no quote). `conditions_for_search/1` powers the `/nutritionist/research` landing count.

## Module map

| Module | File | Role |
|---|---|---|
| `Mehungry.FactMining` | `fact_mining.ex` | Context: `mine_species/1`, `mine_condition/1`, `map_fact_sheet/3`, reads, `research_for_condition/1`, `conditions_for_search/1`. |
| `FactMining.Client` / `ClientBehaviour` | `fact_mining/client.ex`, `client_behaviour.ex` | `POST /mine` + `/health`, bearer-token header. |
| `FactMining.Settings` | `fact_mining/settings.ex` | Singleton UI-managed connection row (`base_url` + JWT `auth_token`), read via `connection/0`. |
| `FactMining.SpeciesMinedFact` / `ConditionMinedFact` | `fact_mining/schemas/…` | One row per mined fact (per species / condition). |
| `FactMining.SpeciesFactMiningRun` / `ConditionFactMiningRun` | `fact_mining/schemas/…` | Per-entity batch tracking row. |
| `FactMining.SpeciesFactMiningRuns` / `ConditionFactMiningRuns` | `fact_mining/…_fact_mining_runs.ex` | Fan-out + progress + PubSub + cancel. |
| `Mehungry.ObanWorkers.{Species,Condition}FactMiningWorker` | `oban_workers/…` | One job == one entity (`:fact_mining`); snoozes on a miner 429 (`{:rate_limited, s}`). |
| `FactMining.QueueLeader` | `fact_mining/queue_leader.ex` | Per-node poller: resumes `:fact_mining` only on the Oban leader (paused elsewhere) → one miner call at a time cluster-wide. |
| `MehungryWeb.ProfessionalLive.FactMiningPipeline` | `…/professional_live/fact_mining_pipeline.ex` | Admin "Mine all species" + live progress. |
| `MehungryWeb.ProfessionalLive.HealthConditions` | `…/professional_live/health_conditions.ex` | Admin "Mine all conditions" card + live progress. |

## What the removal cost (full replacement)

Dropping the species↔compound graph removed every **compound-mediated** read; the **nutrient**
advice engine and **ingredient-level** compound facts (`IngredientCompoundRelationship`) survive:

- `Health.species_for_condition/3` now returns only **directly-curated** species suggestions (no
  compound-derived rows); `Health.ingredients_for_condition/2` returns `[]`;
  `Health.recommendations_for_species/1` was deleted. Condition badges / encouraged-recipe queries are
  now **nutrient-only** (`flags_for_recipes/2`, `combined_encouraged_recipe_ids_query/1`).
- The `/foods` **compound filter** was removed — `/foods` is now search + A–Z browse; species cards
  link to the detail page's new "Research findings".
- `/api/v1/species/:slug` detail replaced its `compounds[]` block with `research[]` (mined facts) —
  see `docs/implementation/new_dec_specs/mobile_api_spec.md`.
- Meal-plan compatibility + recipe-insight dropped their species-layer compound matching (ingredient
  compound facts remain); `Literature.Entrez.search_terms_for_species/1` fell back to keyword terms.

The `compounds` registry, `compound_measurements`, Chemistry, and `EvidenceAggregation` are untouched
(facts-only layers no longer read by advice).

## Testing

```bash
mix test apps/mehungry/test/mehungry/fact_mining_test.exs \
         apps/mehungry/test/mehungry/fact_mining/ \
         apps/mehungry_web/test/mehungry_web/live/professional_live/fact_mining_pipeline_test.exs
```

- **Context** — `query_for_species`, `map_fact_sheet/3` (column flattening, `commercial_ok`-only quote,
  skip-missing + dedup), `mine_species` (insert + counts, wipe-then-insert idempotency, error passthrough).
- **Worker/runs** — fan-out (one row + one job per species), unreachable preflight short-circuit,
  success→completed+counts, retry-then-failed contract, `counts_for_batch` aggregation.
- **LiveView** — renders the page, a terminal broadcast patches a streamed row, non-admin redirect.

## End-to-end (manual)

```bash
cd ../biomed-fact-miner && python3 examples/serve_api.py --demo --port 8811   # offline stub corpus
FACT_MINER_BASE_URL=http://127.0.0.1:8811 iex -S mix phx.server
# /professional/compound-pipeline → "Mine all species", or in IEx: Mehungry.FactMining.mine_species(<id>)
# inspect: Mehungry.Repo.all(Mehungry.FactMining.SpeciesMinedFact)  # non-commercial quotes are nil
```
