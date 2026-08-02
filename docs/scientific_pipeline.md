# Scientific Pipeline — overview & setup runbook

This is the **index and runbook** for the food-science subsystem. Eight detailed
docs each describe one layer; this doc explains **how they compose into one flow**
and gives the **ordered "run X, then run Y" setup sequence** to go from a bare
ingredient list to curated `Ingredient↔Compound` facts and health advice.

Detailed layer docs (read these for the internals of any single stage):
[`chemistry.md`](chemistry.md) ·
[`literature_discovery.md`](literature_discovery.md) ·
[`pubtator.md`](pubtator.md) ·
[`food_compounds.md`](food_compounds.md) ·
[`compound_measurements.md`](compound_measurements.md) ·
[`evidence_aggregation.md`](evidence_aggregation.md) ·
[`compound_candidates.md`](compound_candidates.md) ·
[`health_recommendations.md`](health_recommendations.md).

---

## 1. The big picture

The subsystem has **three phases** and one iron rule that keeps them legible:

```
  ┌─────────────────────────── DISCOVER ───────────────────────────┐
  │  external authorities normalize the world into local registries │
  │                                                                  │
  │   USDA ─────▶ ingredients            (Food.Ingredients)          │
  │   PubMed ───▶ scientific_studies     (Literature / Entrez)       │
  │   PubTator ─▶ study_entity_mentions  (Literature / PubTator3)    │
  │   PubChem ──▶ compounds              (Food.Compounds, via        │
  │                                       Chemistry.Resolver)        │
  └──────────────────────────────┬───────────────────────────────────┘
                                  │  raw evidence — NO dietary facts yet
                                  ▼
  ┌─────────────────────────── CURATE ─────────────────────────────┐
  │  Food.CompoundCandidates — the ONLY layer allowed to write facts │
  │                                                                  │
  │   evidence ──score (noisy-OR)──▶ species_compound_candidates     │
  │      (co-occurrence + measurements,  + reference-study links)     │
  │                    │                                             │
  │        auto ≥0.75 ─┤─ admin Promote/Reject                       │
  │                    ▼                                             │
  │        species_compound_relationships   (curated FACTS)          │
  └──────────────────────────────┬───────────────────────────────────┘
                                  │  facts feed back as targeted crawl terms ↺
                                  ▼
  ┌─────────────────────────── ADVISE ─────────────────────────────┐
  │  Mehungry.Health — the ONLY layer that gives guidance            │
  │                                                                  │
  │   conditions ──▶ compound_recommendations ──▶ compounds          │
  │   Health.species_for_condition/2 resolves the species at read    │
  │   time via the shared compound (ingredients derived via species) │
  └──────────────────────────────────────────────────────────────────┘
```

**Two invariants make the whole design legible:**

1. **Evidence never writes facts directly.** PubTator mentions and literature
   co-occurrence are *evidence*, not assertions. Only `Food.CompoundCandidates`
   (the curation step) may write an `IngredientCompoundRelationship`.
2. **`Food.*` is facts-only; advice is quarantined in `Health`.** Nothing under
   `Food` encodes a recommendation, limit, or severity. Conditions reference
   **compounds**, never ingredients — the implicated foods are *derived* at read
   time through the shared compound.

Everything the app itself reads is a **local registry**; only the adapters
(`Chemistry`, `Literature.Entrez`, `Literature.PubTator`) ever talk to the outside.

---

## 2. Data-flow walkthrough (Spinach → Oxalate → Kidney Stones)

Following one fact through every table:

| # | Table | Row that appears | Written by |
|---|---|---|---|
| 0 | `foundemental_food_species` | `Spinach → Spinacia oleracea` (curated) | admin in the USDA Schema view |
| 1 | `scientific_studies` + `study_ingredients` | a PubMed paper, linked to each ingredient curated onto Spinach with `search_term` | `Literature.Entrez` crawl (per species) |
| 2 | `study_entity_mentions` + `compounds` | `Chemical "oxalate"` mention → resolved to compound **Oxalic acid** (CID 971) | `Literature.PubTator` + `Chemistry.Resolver` |
| 3 | `compound_measurements` *(optional)* | `Spinach, Oxalate, Raw: 750 mg/100g` (PMID …) | `Food.record_measurement/1` |
| 4 | `species_compound_candidates` (+ `species_compound_candidate_studies`) | `Spinach‑species/Oxalate` scored **1.0 (strong)**, `pending`, citing its reference PMIDs | `Food.CompoundCandidates` derive |
| 5 | `species_compound_relationships` | `Spinach‑species contains Oxalate` (`source: literature`) | auto-promote (≥0.75) or admin |
| 6 | `compound_recommendations` + `conditions` | `Kidney Stones → avoid → Oxalate` | `Health.add_recommendation/3` (manual) |
| → | *(derived, not stored)* | `Health.species_for_condition(kidney, :avoid)` yields the **Spinach species** (its ingredients derived through it) | join at read time |

Note the seam between rows 2 and 5: PubTator only records that a paper *mentions*
oxalate near a spinach ingredient (row 2). That co-occurrence, rolled up to the
species, becomes a curated `contains` **fact** (row 5) only after scoring + promotion
(rows 4→5). And the condition (row 6) never names spinach — it names the compound; the
species (and its ingredients) is derived.

---

## 3. Setup runbook (the ordered sequence)

Each stage is an Oban **run-chain** on the `:imports` queue that is idempotent and
self-terminating (a per-item ledger table excludes already-processed items, so
re-running is safe and cheap). Run each from the admin UI **or** IEx.

One unified control panel drives the whole pipeline with **live progress bars**
(PubSub-backed):
- **`/professional/science`** (nav **Science**) — the Science Pipeline panel: a Run
  button + progress bar for every stage (1 crawl, 2 annotation, 4 derivation) and the
  candidate Promote/Reject review queue, all on one page. Each stage's **results** are
  reviewable on their own pages: **Studies** (`/professional/science/studies` — the
  discovered papers, searchable, expandable to linked ingredients + extracted mentions)
  and **Entities** (`/professional/science/entities` — the extracted chemical/species/
  disease mentions and the compounds they resolved into).

The crawl reads each `FoundementalFoodSpecies`' curated `scientific_name` (set by an
admin in the **USDA Schema** view, `/professional/usda-schema`), so there is **no
identity-resolution prerequisite** — a species with a scientific name and at least one
curated ingredient is crawlable.

The two original focused pages still exist and do the same work for a single stage:
- `/professional/literature` — "Run crawl" and "Run annotation" (steps 1 & 2)
- `/professional/compound-candidates` — "Derive" + the Promote/Reject queue (step 4)

### Step 0 — Prereq: curate species + scientific names

The crawler reads each `FoundementalFoodSpecies`' `scientific_name`; **only species
with a scientific name (and at least one curated ingredient) are crawled**, so do this
first. In the **USDA Schema** view (`/professional/usda-schema`) curate USDA
ingredients onto a species and give the species its binomial `scientific_name`
(e.g. `Spinacia oleracea`). `crawl_progress/0`'s `total` counts exactly these
crawlable (named) species.

### Step 1 — Find the papers (literature crawl)

UI: `/professional/science` (or `/professional/literature`) → **Run crawl**. Or:

```elixir
{:ok, _run} = Mehungry.Literature.enqueue_crawl()
Mehungry.Literature.crawl_progress()   #=> %{processed: _, total: _}
```

Builds searches per species as `scientific_name × (linked compounds ∪ generic
keywords)`. On the **first** pass there are no linked compounds, so it uses only the
generic phytochemistry keywords (`phytochemical polyphenol flavonoid antioxidant
bioactive` — `literature/entrez.ex`). Each discovered study is fanned out to **every
ingredient curated onto the species**. Produces `scientific_studies` +
`study_ingredients` / `study_compounds`.
Details: [`literature_discovery.md`](literature_discovery.md).

### Step 2 — Find the compounds (PubTator annotation)

UI: `/professional/science` (or `/professional/literature`) → **Run annotation**. Or:

```elixir
{:ok, _run} = Mehungry.Literature.enqueue_annotation()
Mehungry.Literature.annotation_progress()   #=> %{processed: _, total: _}
```

Annotates each discovered study into `study_entity_mentions` (Chemicals, Species,
Diseases). **This is where compounds actually appear**: each chemical is routed
through `Chemistry.Resolver`, which **populates the `Food.Compounds` registry**
(canonical name, PubChem CID / MeSH / ChEBI identity). Species and diseases are
catalogued but left unlinked. Details: [`pubtator.md`](pubtator.md),
[`chemistry.md`](chemistry.md).

### Step 3 — (Optional) Add quantitative measurements

Records the numbers a paper reports; strengthens candidate scores (step 4) and
enables evidence summaries (step 6). Insert-only and immutable.

```elixir
Mehungry.Food.record_measurement(%{
  ingredient_id: spinach.id, compound_id: oxalate.id, study_id: study.id,
  value: 750.0, unit: "mg/100g", preparation_method: "Raw",
  analytical_method: "HPLC", extraction_method: "manual"
})
```

Details: [`compound_measurements.md`](compound_measurements.md).

### Step 4 — Create the connections (derive + promote candidates)

UI: `/professional/science` (or `/professional/compound-candidates`) → **Derive**. Or:

```elixir
{:ok, _run} = Mehungry.Food.enqueue_candidate_derivation()
Mehungry.Food.candidate_derivation_progress()   #=> %{processed: _, total: _}
```

Reads the evidence — literature **co-occurrence** (a resolved chemical mentioned in a
paper linked to any ingredient of the species) blended with **measurement** evidence
via noisy-OR — and scores each `(species, compound)` pair, recording the reference
studies on each candidate. Candidates scoring ≥ `:candidate_promotion_threshold`
(config, **default 0.75**) **auto-promote** into `species_compound_relationships`;
everything else waits in the Promote/Reject queue on the same page. This is the
**only** step that writes curated facts. Details:
[`compound_candidates.md`](compound_candidates.md).

### Step 5 — Close the loop (re-crawl)

Re-run **Step 1**. Now that relationships exist, `search_terms_for_ingredient/1`
adds targeted `scientific_name × compound` terms (e.g. `Spinacia oleracea oxalate`),
improving recall far beyond the generic keywords. The steady state is a cycle:

```
   Step 1 (crawl) ─▶ Step 2 (annotate) ─▶ Step 4 (derive/promote) ─▶ back to Step 1
```

Each loop discovers more papers → more compounds → more curated facts → better next
crawl.

### Step 6 — Consume the results

```elixir
Mehungry.Food.list_compounds_for_ingredient(spinach.id)     #=> [%Compound{}]
Mehungry.Food.summarize(spinach.id, oxalate.id)             #=> {:ok, %IngredientCompoundSummary{}}
Mehungry.Food.summarize_for_ingredient(spinach.id)          #=> [%IngredientCompoundSummary{}]
```

`summarize/2` computes mean/range/variance + an auditable evidence score over the
measurements (read-only, nothing persisted).
Details: [`food_compounds.md`](food_compounds.md),
[`evidence_aggregation.md`](evidence_aggregation.md).

### Step 7 — Add health advice (separate, manual / guideline)

The advice layer is **not** derived from the pipeline — it is curated by hand or
from clinical guidelines, and it links a condition to a **compound**:

```elixir
Mehungry.Health.add_recommendation(
  %{name: "Kidney Stones", category: "renal"},
  oxalate.id,
  %{recommendation: "avoid", severity: "high", evidence_level: "strong", source: "guideline"}
)

Mehungry.Health.species_for_condition(kidney.id, :avoid)
#=> [%{species: %FoundementalFoodSpecies{name: "Spinach"}, compound: %Compound{name: "Oxalate"}, ...}]
# ingredients_for_condition/2 derives the ingredients strictly through those species.
```

The derived read composes the advice with the step-4 **species** facts through the
shared compound. Details: [`health_recommendations.md`](health_recommendations.md).

---

## 4. Operational notes

- **Queue.** All three run-chains (crawl, annotation, candidate derivation) run on
  the Oban `:imports` queue at gentle concurrency — deliberately kind to NCBI.
- **Rate limits.** Entrez and PubTator enforce NCBI's ceiling via
  `Mehungry.RateLimit`: **3 req/s**, lifted to **10** when the shared
  `NCBI_API_KEY` (`:entrez_api_key`) is set. PubChem is capped at **5 req/s**.
- **Idempotency & termination.** Each stage has a ledger table
  (`literature_crawl_attempts`, `pubtator_annotation_attempts`, the candidate
  natural key) that excludes already-done items, so a batch always terminates and
  re-running never duplicates. A rate-limited batch `{:snooze, _}`s and resumes.
- **Progress.** `*_progress/0` returns `%{processed, total}`; every run also
  broadcasts on `Mehungry.PubSub` (`"literature_crawl_runs"`,
  `"pubtator_annotation_runs"`, `"candidate_derivation_runs"`) for the live bars.
- **Gotchas.**
  - *Manual measurements don't dedupe.* On PostgreSQL 14 (this deployment) NULLs
    are distinct in a unique index, so a `manual` measurement with a `nil`
    `study_id` is never deduped against another. Automated/PDF paths supply the key
    columns and do dedupe.
  - *One study can't read as "Strong".* A pair backed by ≤ 1 study is capped at
    `:limited` in `Food.summarize/2`, regardless of the raw score.
  - *Negative facts never crawl.* Only non-`absent` relationships become crawl
    terms, so an `absent` fact can't leak back in as a search term.
```
