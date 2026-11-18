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
  **The species page renders a _curated_ top set, not the full list (2026-11-14).** A well-studied
  species can carry **thousands** of mined facts; rendering them all bloated the page HTML (~1–2 MB)
  and crawl weight without SEO benefit. So the page renders only the **on-subject verified top ~10**.
  **Diet-relevance ordering + mechanistic collapse (2026-11-16):** `FactMining.curated_facts_for_species/2`
  pulls the verified, non-`hide` pool in the existing lay order (lead-tier → name-mention → `lay_clarity`)
  then **stably re-sorts by evidence altitude** (`Literature.ResearchType.order/1` over `bucket/1`, so
  human/clinical evidence rises ahead of bench chemistry *without* losing the lay ranking within a
  bucket) and **splits** it into `%{relevant, mechanistic, mechanistic_count}`. `relevant` (buckets
  1–7 plus unclassified designs) leads the section; the `:preclinical_other` pile (molecular docking,
  in-vitro, animal — all that a diet-watcher can't read) is demoted into a **collapsed, closed-by-default
  `<details>`** ("Lab & mechanism studies (N)"). When a food's verified findings are *entirely*
  preclinical, they render in the main list under an honest "…preclinical or lab studies rather than
  human dietary research" note instead of a lonely toggle. (`top_facts_for_species/2` — the flat
  verified top-N — remains for other callers; the species page now uses the split read.) The
  honest header tally (`✓ corroborated · ✕ contradicted · unverified`) still reports the **true**
  totals via a cheap grouped count (`research_counts_for_species/1`), independent of the curated slice.
  Everything the top set omits — contradicted, unverified, and off-subject (`lay_tier == "hide"`)
  facts — is reached on demand through a **server-side fuzzy search box** (`phx-change` →
  `search_facts_for_species/3`, a case-insensitive `ILIKE` on `text` across **all** labels/tiers,
  capped). Each row still carries a verdict-colour left rail + badge, an acronym-correct study-design
  chip (`SpeciesDetailLive.study_design_label/1` — fixes the `Phoenix.Naming.humanize("rct") => "Rct"`
  miscasing), the PMID link, and a per-fact **"Why?"** that expands the mined `reason`. The
  uniform-`very_low` `certainty` is intentionally **not** shown. (The search box needs the socket, so
  it is inert on the dead render — crawlers index the curated verified list, which is the point.)
- **Condition** (`ConditionMinedFact`, table `condition_mined_facts`) — a **relational** query
  `"give me all the food related facts about {condition}"`, feeding the nutritionist research surface
  (`research_for_condition/1`, `conditions_for_search/1`); each mined PMID is enriched into the
  `ScientificStudy` registry for publication-card metadata.

## The external service (biomed-fact-miner)

A FastAPI pipeline (sibling repo `/home/nikolis/git/biomed-fact-miner`). `POST /mine` returns a
`FactSheet.to_dict()`: `{query, scope_kind (entity|relational|out_of_scope), counts, facts[], trace[]}`.
Each `facts[]` element wraps a verdict (`label`, `certainty`, `reason`, `conflicting_pmid`,
`assessment`, **`lay`**) around an inner fact (`fact_id`, `text`, `claim_type`, `pmid`, `quote`,
`char_span`, `study_design`, `source`, `pmcid`, `doi`, `pub_status`, `structured_effect`, `license`,
`license_raw`).

**`lay`** (added 2026-11-14) is a **presentation hint orthogonal to `label`** —
`%{tier: "lead"|"show"|"hide", clarity: float[0,1], flags: [...]}`. The rule is "relevance decides
visibility, clarity only decides prominence": `hide` = the fact is **not about the query subject**
(off-subject comparators/background), `lead`/`show` = on-subject sorted by readability `clarity`;
`flags` carry the demotion reasons (`off_subject:<relation>`, `undefined_acronym:<ACR>`, …). The
miner never trims — every fact stays in the payload; filtering is the client's call. We flatten it
into `lay_tier` / `lay_clarity` / `lay_flags` columns on **both** mined-fact tables (shared ingest)
and the species page uses `tier`+`clarity` to pick its curated top set and to push off-subject facts
into search-only. Facts mined before the miner exposed `lay` have NULL `lay_*` (kept, not hidden)
until the next wipe-insert re-mine.

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

## Single-entity mining with a customizable prompt (2026-11-15)

Mining is invoked **one entity at a time**, and the **prompt is editable per mine** (pre-filled with
the default `query_for_species/1` / `query_for_condition/1`). The bulk fan-out (`mine_all_species/0`
/ `mine_all_conditions/0`) is **kept dormant** — the context functions + their tests remain, but no UI
triggers them (removed 2026-11-15). Each single mine still rides the exact same Oban + per-unit
tracking-row + PubSub path (`docs/reference_architecture/oban_ui_connected_worker.md`) as a **one-row
batch**, so the live-progress machinery is unchanged; only the fan-out and the fixed prompt are gone.

**How the custom prompt threads down.** `FactMining.mine_species/2` / `mine_condition/2` take an
optional `opts[:query]` that overrides the prompt sent to `client().mine/2` (blank/nil → the default
builder, via a `presence/1` guard). The chosen prompt is **persisted** on the tracking row (`query`
`:text` column on both run tables) **and** carried in the Oban job args (`"query"`), so the worker
reads `args["query"]` and forwards it (`mine_species(id, query: args["query"])`). Dormant bulk jobs
carry `nil` → default. A re-mine is still wipe-then-insert idempotent.

## Species mining — the admin pipeline (Oban-UI-connected)

`/professional/compound-pipeline` (`MehungryWeb.ProfessionalLive.FactMiningPipeline`, admin-gated;
route reused from the retired page). The page is a **"Mine one species" form** — a **searchable
species picker** (`MehungryWeb.SelectComponent`, type-to-filter; rows already mined are annotated via
`item_meta` with "N facts", or "mined · 0 facts" when a run completed but yielded none, from
`FactMining.fact_counts_by_species/0` + `SpeciesFactMiningRuns.species_with_completed_runs/0`) whose
selection pre-fills the prompt `<textarea>` with the default (via the form's `mine_changed`
`phx-change`), editable before submit:

```
Mine species (form: species_id + query) ─▶ SpeciesFactMiningRuns.mine_species/2
  preflight reachable? + get_foundemental_species/1 existence + one-in-flight guard
    (active_mine_for_species/1 → {:error, {:already_running, id}} + admin flash)
  one `pending` species_fact_mining_runs row (query stored) ─ one SpeciesFactMiningWorker job
                                   │       (job args carry "query")
  :fact_mining queue (concurrency 1) ─ one job == one species
    SpeciesFactMiningWorker.perform ─▶ FactMining.mine_species(id, query: args["query"]) (wipe + insert)
                                   │        mark_processing → mark_completed | mark_failed
                                   ▼
  PubSub "species_fact_mining_runs" ─▶ LiveView streams per-species rows (O(1) patch),
    slim {:fact_mining_processing, batch, species} coalesced behind a ~400ms flush timer;
    full {:fact_mining_run, row} on terminal. Aggregate progress = counts over batch_id.
```

- `species_fact_mining_runs` — **one row per species per `batch_id`** (status `pending → processing →
  completed | failed`, `facts_total` / `verified_count` / `contradicted_count`, `query`, `error`). The
  LiveView streams these and derives batch progress by counting over `batch_id` (no separate aggregate
  table).
- Worker (`:fact_mining`, `max_attempts: 3`): a transient miner failure returns `{:error, _}` so Oban
  retries (wipe-then-insert is idempotent); on the **final** attempt the species is recorded `failed`
  so the batch still finalizes. `cancel_batch/1` cancels remaining jobs + marks unfinished rows
  `cancelled` (a neutral status, distinct from `failed`, that doesn't count toward "Failed" or show red).
- **The row is reverted to `pending` whenever the job yields its slot without finishing** — a 429
  `:snooze` or a non-final error retry (`Runs.mark_pending/1`). The worker only ever moves a row
  *forward* (`mark_processing` on run-start → terminal), so without this a snoozed/retrying job would
  leave its row stuck `processing` even though it is no longer executing. With `limit: 1` that leak
  made a serialized batch falsely read as "**every species `processing` at once**" (the symptom the
  admin sees: one job runs, but each species that took a turn and snoozed/retried stays `processing`).
  Reverting keeps exactly the one truly-executing row `processing` and the rest `pending`.

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
- **Client timeout must exceed the miner's per-call duration (the serialization premise).** The whole
  one-at-a-time scheme assumes each `FactMining.Client.mine/2` call **blocks until the miner answers**,
  so the single `:fact_mining` slot is held for the full call and no second `/mine` can fire. An HTTP
  client timeout does **not** cancel the server-side work — if the client gives up early, the miner
  keeps processing the abandoned request while the freed slot starts the next job and fires *another*
  `/mine`, so over a batch the requests pile up and overlap on the miner even though Oban only ever ran
  one `perform` at a time. A single `/mine` can take **up to ~10 min**, so the client default is
  **15 min** (`@default_timeout_ms`, overridable via `:fact_miner_timeout_ms` / `FACT_MINER_TIMEOUT_MS`
  — only ever *raise* it). The old 120s default silently broke this: every call was abandoned at 2 min
  and the next job re-fired, which is exactly how "all species query the REST API at once" happened.
- **429 / `Retry-After` (reactive safety net).** The miner enforces its **own** concurrency limit and
  returns **HTTP 429** when saturated. `FactMining.Client.mine/2` maps that to
  `{:error, {:rate_limited, seconds}}` (parsed from the `Retry-After` header, defaulting to 30s,
  clamped ≥5s); both workers turn it into `{:snooze, seconds}` — rescheduling **without** burning a
  retry or marking the run failed, and **reverting the tracking row to `pending`** (it gave up its slot
  and is no longer executing). This covers any brief overlap during a leadership handoff.

> **Prod note (2026-11-15):** a Broccoli mine actually ran **~19 min** (the miner interpreted
> `max_records: 200` loosely and returned 2632 facts), overshooting the 15-min client default — the
> client abandoned the request at 15 min with `{:network, :timeout}` and the completed response (391
> verified facts) was discarded, then the job retried the same overshoot. Fixed by setting
> `FACT_MINER_TIMEOUT_MS=1800000` (30 min) in prod. The repeated timeouts also saturated the miner,
> which returned 429s that snoozed the bulk jobs' `max_attempts` up into the hundreds (each `:snooze`
> bumps `max_attempts`), leaving a days-long retry backlog that was cancelled.

### One in-flight mine per entity (duplicate-trigger defense)

A per-entity mine is **singleton in the queue**: re-triggering a species/condition that already has a
job `available/scheduled/executing/retryable` is **refused and surfaced to the admin**, not silently
duplicated. Re-mining an entity whose previous mine has **completed** stays allowed (mining is
wipe-then-replace). Two complementary layers, symmetric across species + condition:

- **App-level pre-check (the notification).** `active_mine_for_{species,condition}/1` queries `Oban.Job`
  for a live job on that entity id; `mine_{species,condition}/2` returns `{:error, {:already_running,
  id}}` before enqueuing, and the LiveViews flash *"already has a mine in the queue — wait for it to
  finish or cancel it first"* (`FactMiningPipeline` `handle_async(:mine_one, …)`; `HealthConditions`
  `handle_async({:mine_condition, cid}, …)`).
- **Oban `unique` backstop (race-proof).** Both workers declare
  `unique: [keys: [:species_id|:condition_id], states: [:available, :scheduled, :executing, :retryable],
  period: :infinity]` (`completed`/`discarded`/`cancelled` excluded, so a finished entity is re-minable).
  The single-entity path enqueues via **`Oban.insert/1`** (not the bulk `insert_all`, which bypasses
  uniqueness) through `enqueue_one/2`; if the insert comes back `conflict?: true`, the just-opened
  tracking row is deleted (no orphan `pending` row) and `:already_running` is returned. The dormant
  bulk `mine_all_*/0` keeps `enqueue_batch/2` + `insert_all` unchanged.

## Condition mining — the admin trigger on `/professional/health`

The condition branch mirrors the species path exactly, from a different admin surface. The **"Mine
conditions (fact-miner)"** card on `/professional/health` (`MehungryWeb.ProfessionalLive.HealthConditions`)
replaced the old extractor "Research ingestion" card.

**Page action hierarchy (2026-11-14).** The header keeps only the secondary `Compound pipeline →`
link plus two Alpine dropdowns — a **Setup** menu (`Seed registry`, `Seed diet patterns`) and a
paprika **Danger zone** menu (`Clear all suggestions`, `Wipe extractor data`) — so the rare and the
irreversible actions no longer share size/billing with everyday work; the buttons keep their exact
`phx-click` + `data-confirm` (still directly addressable in tests). The "Mine conditions" card is now
just intro copy + the miner-reachability indicator; mining is **per-condition** from each card.

**Per-condition mine with an editable prompt (2026-11-15).** Each condition card's **"Mine facts"**
button fires `open_mine_modal` → a `core_components.ex` `<.modal>` pre-filled with that condition's
default prompt (`FactMining.query_for_condition/1`). The admin edits the prompt and submits the modal
form (`phx-submit="mine_condition"`, textarea `name="query"`); the handler reads the condition from the
open modal's assign + the query from the form and starts a one-row mine. The bulk **"Mine all
conditions"** button + its progress bar / ETA line / sticky mini-status were **removed** with the
fan-out (the dormant `mine_all_conditions/0` stays).

> **Extractor UI fully retired + data wipeable (2026-11-14).** With the fact-miner the sole source of
> nutritionist condition research, the page's remaining extractor affordances — the "Analyzer service"
> settings, "Analyze selected", analyzed/unusable badges, and the per-condition "Claims & suggestions"
> verify→publish tabs — were **removed**. A one-shot **"Wipe extractor data"** admin button calls
> `Mehungry.Science.PipelineReset.reset_extractor_data/0`, clearing `study_analyses`, extractor-sourced
> `study_full_texts` (`source = "mehungry_extractor"`), the `extractor_settings` singleton, and all
> `research_ingestion_runs`. The underlying `Extractor` / `StudyAnalyses` / `ResearchIngestion`
> contexts and the legacy in-app reader remain dormant-but-intact.

A single condition is mined from its card (the modal flow above):

```
Mine facts (modal: query) ─▶ ConditionFactMiningRuns.mine_condition/2 (condition_id, query)
  preflight reachable? ─ one `pending` condition_fact_mining_runs row (query stored)
  ─ one ConditionFactMiningWorker job (args carry "query")
                                   │
  :fact_mining queue (concurrency 1) ─ one job == one condition
    ConditionFactMiningWorker.perform ─▶ FactMining.mine_condition(id, query: args["query"])
                                   │        (wipe + insert + enrich PMIDs)
                                   │        mark_processing → mark_completed | mark_failed
                                   ▼
  PubSub "condition_fact_mining_runs" ─▶ the LiveView routes the terminal event by `batch_id`
    (single_batch_ids) back to the card: clears "Mining…" + flashes "Mined N facts".
```

Both `mine_condition/2` and the dormant `mine_all_conditions/0` share the private `enqueue_batch/2`
(`query` nil for the bulk path → the worker falls back to the default builder). The per-condition mine
opens a **one-row batch** on its own `batch_id`; its progress is the card's own "Mining…" state + a
result flash, routed by `batch_id`.

`mine_condition/2` additionally **enriches** each distinct `pmid` via `Literature.fetch_and_upsert_study/1`
(cached — the stored row is returned with no network when present) so publication cards carry real
title/journal/authors/year + MEDLINE badge. The miner returns only PMID/PMCID/DOI.

The nutritionist then reads it offline: `FactMining.research_for_condition/1` groups the stored facts by
`pmid` into **publications**, tagged **presentable** when `license == "commercial_ok"` (shown with their
verbatim quotes, grouped by research type) vs a flat **free-claims** section (distilled wording + a
source link, no quote). `conditions_for_search/1` powers the `/nutritionist/research` landing count.

**Within-condition search (2026-11-18).** `FactMining.search_condition_research/2` is a full-text
search over one condition's research, returning a flat **rank-ordered** list of the same
`build_publication/3` publication maps (plus `:rank` and `:matched_in_finding`). Ranking is a
**weighted `tsvector`**: a publication's findings (`text` + `quote`) sit in band **A**, its `title`
in **B**, its `abstract` in **C**, scored by `ts_rank_cd(websearch_to_tsquery('english', unaccent(q)))`
— so a term appearing **as a finding** outranks one that only appears in the title/abstract (the
nutritionist's requirement). It's **query-time, no migration/materialized view** (per-condition
corpora are small); a `?::text = ?` left-join bridges the string `f.pmid` to the integer `s.pmid`, and
result ordering (`rank` desc, `verified`-present tie-break — a tie-break, *not* a score multiplier, so
weak/contradicted matches stay visible, then the usual publication sort) happens in Elixir. Matching is
**abstract-level only** — full paper body is not indexed.

**Global cross-condition search (Phase 2, 2026-11-18).** `FactMining.search_all_research/2` searches
*every* condition's research at once and returns **one card per PMID** — `%{pmid, study_id, card_rank,
any_in_finding, conditions: [%{condition_id, condition_name, label, finding_text, in_finding}], study,
abstract_snippet}` (+ `study_meta` fields). It reads a **`research_search` materialized view** (one row
per `condition_mined_fact`: `document` = findings`text`+`quote` **A** / `title` **B** / `abstract`
**C**, plus a findings-only `finding_tsv` to tell "matched in a finding" from "matched in abstract").
The query ranks each row (`ts_rank_cd`), keeps the best finding per `(pmid, condition)` (`DISTINCT ON`),
then `GROUP BY pmid` → `jsonb_agg` the per-condition rows (verified-first) with `MAX(rank)` as the card
sort and `bool_or(in_finding)` as the card cue. **Abstract-inclusive**: a paper surfaces on an abstract
hit even with no matching finding (`any_in_finding: false` → `abstract_snippet` shown); abstract sits in
band C so those cards rank last. PMID dedupe is exact `GROUP BY` (not entity resolution); every
per-condition row keeps its own label (never collapsed). Capped at 50. The MV is **refreshed app-side**
by `FactMining.refresh_research_search/0` (`REFRESH MATERIALIZED VIEW CONCURRENTLY research_search`),
called from `ConditionFactMiningWorker`'s success branch **after** `mine_condition/2` commits (NOT a DB
trigger — CONCURRENTLY can't run in the mine's wipe-insert transaction; best-effort, a refresh failure
never fails the mine). Migration: `…_create_research_search.exs` (GIN index on `document`, unique index
on `fact_row_id` for CONCURRENTLY). Within-condition search stays query-time (no MV). See
`docs/features/professionals/research_search.md`.

## Module map

| Module | File | Role |
|---|---|---|
| `Mehungry.FactMining` | `fact_mining.ex` | Context: `mine_species/2`, `mine_condition/2` (optional `opts[:query]` prompt override → default builder when blank), `map_fact_sheet/3`, species reads (`list_facts_for_species/2` full · `curated_facts_for_species/2` diet-relevance-split SEO set · `top_facts_for_species/2` flat verified top-N · `research_counts_for_species/1` tally · `search_facts_for_species/3` on-demand fuzzy), `research_for_condition/1`, `search_condition_research/2` (within-condition weighted-tsvector search, findings=A/title=B/abstract=C), `search_all_research/2` (global, one card per PMID, over the `research_search` MV), `refresh_research_search/0` (rebuild that MV post-mine), `conditions_for_search/1`. |
| `FactMining.Client` / `ClientBehaviour` | `fact_mining/client.ex`, `client_behaviour.ex` | `POST /mine` + `/health`, bearer-token header. |
| `FactMining.Settings` | `fact_mining/settings.ex` | Singleton UI-managed connection row (`base_url` + JWT `auth_token`), read via `connection/0`. |
| `FactMining.SpeciesMinedFact` / `ConditionMinedFact` | `fact_mining/schemas/…` | One row per mined fact (per species / condition). |
| `FactMining.SpeciesFactMiningRun` / `ConditionFactMiningRun` | `fact_mining/schemas/…` | Per-entity batch tracking row (carries the mined `query`). |
| `FactMining.SpeciesFactMiningRuns` / `ConditionFactMiningRuns` | `fact_mining/…_fact_mining_runs.ex` | `mine_species/2` · `mine_condition/2` single-entity enqueue (query → row + job args) via `enqueue_one/2` (one `Oban.insert/1` with the uniqueness backstop) + progress + PubSub + cancel; `active_mine_for_{species,condition}/1` pre-check → `{:error, {:already_running, id}}` on a duplicate trigger; dormant `mine_all_*/0` bulk fan-out shares the private `enqueue_batch/2`. |
| `Mehungry.ObanWorkers.{Species,Condition}FactMiningWorker` | `oban_workers/…` | One job == one entity (`:fact_mining`), `unique` keyed on the entity id across non-terminal states (one in-flight mine per entity); forwards `args["query"]` to `mine_*/2`; snoozes on a miner 429 (`{:rate_limited, s}`), reverting its row to `pending` (also on a non-final error retry) so a yielded slot doesn't leave the row stuck `processing`. |
| `FactMining.QueueLeader` | `fact_mining/queue_leader.ex` | Per-node poller: resumes `:fact_mining` only on the Oban leader (paused elsewhere) → one miner call at a time cluster-wide. |
| `MehungryWeb.ProfessionalLive.FactMiningPipeline` | `…/professional_live/fact_mining_pipeline.ex` | Admin "Mine one species" form (searchable `SelectComponent` picker annotated with each species' mined-fact state + editable prompt) + live progress (counts incl. neutral `cancelled`). |
| `MehungryWeb.ProfessionalLive.HealthConditions` | `…/professional_live/health_conditions.ex` | Admin Conditions list; per-condition "Mine facts" button → prompt modal (`open_mine_modal` → `mine_condition/2`) + live card state. |

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

- **Context** — `query_for_species`, `map_fact_sheet/3` (column flattening incl. `lay_*`,
  `commercial_ok`-only quote, skip-missing + dedup), `mine_species` (insert + counts, wipe-then-insert
  idempotency, error passthrough), **`mine_species/2` / `mine_condition/2` custom prompt** (`opts[:query]`
  sent verbatim; blank/nil → default builder — asserted via `ClientStub.last_query/0`), species reads
  (`top_facts_for_species/2` — verified-only, `hide` excluded, lead/clarity/name-term order, `:limit`;
  `research_counts_for_species/1` tally; `search_facts_for_species/3` — all-labels match, blank → `[]`).
- **Species page** (`species_detail_research_test.exs`) — dead render caps verified facts at 10 while
  the tally reports the true total; `hide`/non-verified excluded from the curated set; connected search
  surfaces the contradicted/off-subject facts the curated set omits.
- **API** (`food_json_test.exs`) — `research[].lay` serialized (`flags` defaults to `[]`).
- **Worker/runs** — `mine_species/2` single-entity enqueue (one row + one job, `query` on row + args),
  unreachable / `:not_found` short-circuits, worker forwards `args["query"]` (nil → default),
  success→completed+counts, retry-then-failed contract, `counts_for_batch` aggregation; dormant
  `mine_all_species/0` fan-out still covered. **One-in-flight defense** — a second `mine_{species,
  condition}/2` while a job is live returns `{:error, {:already_running, id}}` leaving exactly one job +
  one row, `active_mine_for_{species,condition}/1` reflects the live job, a different entity still
  enqueues, and a completed job no longer blocks a re-mine.
- **LiveView** — species page renders the mine-one form, the searchable picker pre-fills the prompt, form submit
  opens a one-row batch carrying the edited query; condition page opens the per-condition mine modal
  (pre-filled), submit mines with the edited query, non-admin redirect. Re-submitting a species that
  already has a queued mine flashes "already has a mine in the queue" and adds no duplicate job.

## End-to-end (manual)

```bash
cd ../biomed-fact-miner && python3 examples/serve_api.py --demo --port 8811   # offline stub corpus
FACT_MINER_BASE_URL=http://127.0.0.1:8811 iex -S mix phx.server
# /professional/compound-pipeline → pick a species, edit the prompt, "Mine species"
#   (or in IEx: Mehungry.FactMining.mine_species(<id>, query: "custom prompt"))
# /professional/health → a condition's "Mine facts" → edit the prompt in the modal → "Mine"
# inspect: Mehungry.Repo.all(Mehungry.FactMining.SpeciesMinedFact)  # non-commercial quotes are nil
```
