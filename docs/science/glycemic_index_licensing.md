# Glycemic Index — licensing & provenance

**Status: decision doc for the GI pivot.** The pipeline in
[`glycemic_index.md`](glycemic_index.md) was built to ingest the *compiled* 2021
International Tables. That compilation is **not licensable for commercial use**, so
the source-of-truth changes from "the table" to "the primary studies the table cites."
This doc records why, what's legally defensible, and what changes in the code. Nothing
has been ingested yet (`priv/data/glycemic_index/` holds only a README), so this
re-provenancing happens before any data is committed — a clean pivot.

## The problem

The **International Tables of Glycemic Index and Glycemic Load Values 2021**
(Atkinson, Brand-Miller, Foster-Powell, Buyken, Goletzke; *AJCN*,
[doi:10.1093/ajcn/nqab233](https://doi.org/10.1093/ajcn/nqab233)) is a copyrighted
**compilation** © American Society for Nutrition / Oxford University Press. Shipping
its Supplemental Tables 1 & 2 as our dataset — serving those values to paying users —
is the exposed use we cannot license.

> **Not legal advice.** This is engineering-level analysis to steer the design. Get
> counsel to sign off before shipping GI values to users.

## Two legal regimes — and the one that binds us

| Regime | What's protected | What's free | Bearing on us |
|---|---|---|---|
| **US copyright** (*Feist v. Rural*, 1991) | The compilation's original **selection / coordination / arrangement** | The individual GI **values** — facts aren't copyrightable | Copying values ≠ infringement; copying the table's curation/structure is |
| **EU sui generis database right** (Directive 96/9/EC) | The **substantial investment** in obtaining/verifying/presenting the DB | Independent re-creation from primary sources | Extracting/re-utilizing a *substantial part* infringes **even without copying arrangement** |

We deploy in **`eu-central-1`** with a first-class Greek locale, so the **EU database
right is the binding constraint** — the stricter of the two. Designing to satisfy it
satisfies both.

## Three uses, three verdicts

1. **Ship the compiled table's values** (ingest the CSV/PDF rows, serve them) —
   ❌ *exposed.* This is textbook extraction of a substantial part of their database.
   This was the original pipeline's model. It's the thing we're retiring.

2. **Re-derive each value from the primary citation** — ✅ *defensible*, with two
   non-negotiable conditions:
   - **Use their reference list only as a bibliography/roadmap, never as the answer
     key.** A list of PMIDs/DOIs is not the protected value-database; but if we
     systematically mirror *their* choice of which value to record, an EU regulator
     can still call that re-utilization. Each value must be genuinely read from the
     **primary paper**, with that paper as the record's provenance.
   - **Extract the numeric fact, not the paper's text.** Primary papers are themselves
     copyrighted; the measured GI number is a fact we may extract and store, but we
     don't redistribute their prose/tables.

3. **Use the PDF internally to QA our re-derived data** (coverage %, spot-check
   correctness) — ✅ *defensible internal reference use*, distinct from redistribution.
   Keep it strictly internal: never ingest it into a served table, never expose it,
   never commit the PDF to the repo. It is a private measuring stick, not a source.
   This is what the verification harness ([task 3](#)) does.

## Empirical reality of the source (measured from the PDFs, 2026-08-21)

Inspecting `studies/SupplementalTable1.pdf` (139 pp, A4) turned up two facts that
**cap what any re-derivation can achieve** — decide scope with these in hand:

- **~51% of Table 1 is unpublished.** Of ~2091 data rows, **1068 cite an
  "unpublished observations" footnote** rather than a paper (UO5 = Sydney University
  GI Service: **847 rows**; UO7 = INQUIS/GI Labs Toronto: 109; UO10 Int'l Diabetes
  Institute: 55; plus smaller labs). These values **exist only in this compilation** —
  there is *no primary paper* behind them, so **no re-derivation route (A or B) can
  recover them.** They are exactly the values we can't license and can't reproduce.
- **The numbered reference list is not in the supplemental PDFs.** Table 1 contains
  the value table + 26 explanatory footnotes only — no bibliography, no DOIs/PMIDs. The
  Ref-column numbers (`3`, …) resolve against the **main AJCN article's** reference
  list, which we do **not** have. **Path A cannot start** until that bibliography is
  obtained (main paper or its reference supplement).

**Consequence:** re-derived coverage of Table 1 has a hard ceiling around **~49%**
(the ~1028 rows that cite a real paper). The unpublished ~51% is only obtainable by
licensing the compilation. This is a scope decision, not a coding one.

**Table 2 is the opposite** (measured from `SupplementalTable2.pdf`, 136 pp): of ~1504
rows only **~3.5% are unpublished** — **~96.5% cite a real paper**. So the
"lower-quality" table is the *more* reproducible food set under path B. Combined
re-derivable target across both tables ≈ **~2480 published GI entries** (1028 + 1452).
Path B (independent Entrez discovery) reaches this set without needing the main
article's bibliography at all — another reason it beat path A.

## Why this fits the architecture we already have

Re-derivation isn't a new subsystem — it's the **existing literature pipeline** applied
to a new extraction target:

```
Entrez discovery (PMID)  →  PMC full text  →  extract measured GI value
   →  GlycemicIndexRecord (provenance = primary PMID/DOI, not "the 2021 table")
   →  GlycemicIndexCandidate (name-match to species, review-gated)
   →  IngredientScientificProperty (glycemic_index, glucose=100)
```

Two things already line up:

- **`GlycemicIndexRecord` is already shaped for per-study provenance.** It carries
  `reference`, `country`, `year`, `sample_analysis_method`, `subject_count`,
  `available_carb_g`, `test_portion_g` — i.e. a record can represent *"GI as measured
  in study PMID X"* just as easily as *"row N of Table 1."* The value + SEM + method +
  subject count are exactly a single-study measurement.
- **The candidate/review gate is unchanged.** Match-to-species, confidence scoring,
  auto-promote-narrowly, promote/undo fan-out — all still apply. Only the *upstream
  source* of a record changes.

## What changes in the code (feeds the re-arch task)

| Today (compilation model) | After (primary-study model) |
|---|---|
| `quality_tier: "table1" \| "table2"` (which supplemental table) | Grade quality from the **primary paper itself** — ISO-26642 method? subject count? — not from which table it sat in |
| One shared `IngredientEnrichmentSource` = "the 2021 dataset", stamped on every record (`@dataset_identifier "intl_gi_2021"`) | One enrichment source **per primary study** (PMID/DOI), so each promoted property cites the study it actually came from |
| `TableParser` (CSV → rows) is the ingest path | Ingest path is literature extraction (PMC full text → GI value); `TableParser`/`mix gi.ingest` demoted to the **internal verification harness** only |
| Auto-promote gate: `table1 AND exact_name` | Auto-promote gate re-expressed on the new quality signal (e.g. `iso_26642_method AND exact_name`); default stays deliberately narrow |
| `row_ref` = food number / row index | `row_ref`/natural key becomes the study identifier (+ within-study food key) |

The **promote/reject/undo fan-out logic is preserved** — it operates on a candidate +
species, agnostic to where the value came from. The `GlycemicIndexCandidate` schema is
reshaped from *record→species name-match* to *study→species extracted value* (see below).

## Re-architecture status (built)

The core re-arch is done, compiling, and tested — GI now mirrors the
compound-measurement pipeline:

- **Schema/migration** — `glycemic_index_candidates` reshaped to a single study-based,
  review-gated table (`study_id` + `foundemental_species_id` + `gi_value`/`gi_sem` +
  `iso_method` quality flag + extraction bookkeeping + `promoted_property_ids`); the
  `glycemic_index_records` / `_match_runs` tables and `quality_tier` are gone.
- **`Food.GlycemicIndex`** — `record_extracted_gi/3` fans an extracted finding over the
  study's species into pending candidates (cited per-study via a `doi`/`url`
  `IngredientEnrichmentSource`); promote/reject/undo preserved; **no auto-promotion**
  (a study can test several foods). Facade delegates updated.
- **Retired** — `GlycemicIndexRecord`, `GlycemicIndexMatchRun(s)`,
  `GlycemicIndexMatchWorker`, `TableParser`, `mix gi.ingest` (backed up outside git).
- **Discovery** — the Entrez crawl gained a `"glycemic index"` term per species
  (`@glycemic_keywords`), so GI feeding-trial studies are discovered independently.
- **Review UI** — `/professional/glycemic-index` reworked to a review-only queue
  (species · GI value · ISO badge · study link); no ingest/match controls.

**Local-AI GI extractor (built).** The extraction that populates the review queue is
done, reusing the measurement-extraction plumbing (`docs/ai/measurement_extraction.md`):

- `MehungryLocalAi.Extractor.gi_findings/1` — a rule-based GI extractor over a paper's
  PMC full text (value + SEM anchored on a "glyc(a)emic index" / "GI value of N" mention
  so the *gastrointestinal* sense of "GI" doesn't false-match; also lifts `iso_method`,
  `reference_food`, `sample_size`, `analytical_method`). Values clamped to a plausible GI
  range; deduped.
- `/pending` now returns `extract_gi: true` for GI-discovered studies
  (`Literature.gi_discovered?/1` — a study with a `… glycemic index` `StudyIngredient`
  term). The `mix local_ai.extract` pass runs GI extraction over the **same** full text
  it already fetched for compounds and POSTs findings to the new
  `POST /api/local_ai/gi_candidates`.
- `GiCandidatesController` fans each finding over `Literature.species_ids_for_study/1`
  into `Food.record_extracted_gi/3` → pending `GlycemicIndexCandidate`s (review-gated,
  no auto-promotion).

So the full path-B loop now runs: **crawl → PMC full text → GI extraction → review queue
→ promote → `IngredientScientificProperty`**, with the offline **`mix gi.diff`** harness
(above) available to measure the re-derived values against the PDF oracle.

## Decision

- **Retire** the compiled-table-as-source model (use #1).
- **Adopt** primary-citation re-derivation (use #2) as the data source, reusing the
  literature → extraction → candidate → review pipeline.
- **Discovery path: B — independent Entrez keyword discovery.** Chosen over the
  Tables' reference-list roadmap (path A), after the empirical findings above showed A
  is both blocked (no bibliography in the supplemental PDFs) and capped at ~49%. Under B
  the compilation is touched **only** by the verification harness — never for discovery,
  never as a roadmap. Discipline:
  - GI studies are discovered through the **existing literature crawl**: each
    `FoundementalFoodSpecies` is crawled by `scientific_name × keywords`, adding
    `"glycemic index"` (and near-synonyms) as keywords. This is a fully independent
    re-creation from primary sources — the **strongest EU posture**.
  - **The stored GI value comes from the primary paper we fetch, extracted by us.** The
    Table's value is used *only* by the verification harness (use #3) to check our
    independently-extracted number against the published one — it is never the number we
    persist or serve.
  - **Coverage is whatever PubMed yields**, not the Table's food set. The unpublished
    ~51% of Table 1 is unreachable (it isn't in PubMed) — an accepted gap, not a bug.
- **Keep** the PDF strictly as an internal verification oracle (use #3): parsed into a
  reference set that the harness diffs our re-derived values against. Never committed
  (`studies/` is git-ignored), never ingested-as-served, never exposed.

## Verification harness (built)

The internal oracle half of the harness exists:

- `Mehungry.FoodData.GlycemicIndex.PdfReferenceParser` — parses
  `studies/SupplementalTable{1,2}.pdf` (via `pdftotext -layout`, form-feed page-split,
  food-number/`±`/year anchored columns) into structured rows: `food_item`, `gi_value`,
  `gi_sem`, `country`, `year`, `ref_code`, `unpublished`, `category`, `source_table`.
- `mix gi.verify [PATH] [--table] [--out FILE]` — prints coverage stats (rows, UO share,
  re-derivable ceiling, categories) and optionally dumps the reference rows as JSON.
- Extraction fidelity on the real PDFs: **100%** of GI values, **~98%** food names
  (Table 1). Known residual: the first entry under each subcategory / first row on a
  page can carry a short subcategory or header fragment as a name prefix — cosmetic for
  fuzzy matching, never affects a value. UO rows are flagged `unpublished: true`.

The *diff* half is built too:

- `Mehungry.FoodData.GlycemicIndex.OracleDiff.compare/3` (pure) — fuzzy-matches each
  *publishable* oracle food to one of our species carrying a re-derived value and buckets
  the pair **agree** (within `:tolerance` GI units) / **diverge** ("investigate") /
  **uncovered**; also surfaces `orphan_species` (re-derived values with no oracle match).
  Unpublished `UO` rows are counted as expected gaps, not misses.
- `Food.rederived_glycemic_by_species/1` loads our re-derived values (from
  `GlycemicIndexCandidate`, grouped by species) as the diff's second input.
- `mix gi.diff [PDF] [--tolerance N] [--out FILE]` wires PDF + DB together and prints
  coverage / agreement / top divergences (dumps the divergence + orphan detail as JSON
  with `--out`).

With no re-derived data yet it reports 0% coverage over the 1028 publishable Table-1
rows (the plumbing runs; there's just nothing to match). Once a crawl + extraction pass
has produced candidates, this is the "how complete / how correct is our data" report.

Reminder: this is a **measuring stick, not a source** — the parser output is never
ingested-as-served, and `studies/` is git-ignored.

See [`glycemic_index.md`](glycemic_index.md) for the pipeline mechanics and
[`scientific_pipeline.md`](scientific_pipeline.md) for how literature discovery/
extraction is wired.
