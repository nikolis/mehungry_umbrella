# Food Science Pipeline — Overview

How the food-science subsystem turns external authorities (USDA, PubMed, PubTator,
PubChem) into curated `Species↔Compound` facts and, finally, dietary advice. This
is the front door to `docs/science/` — each section links to the doc that covers it
in depth.

The subsystem runs **DISCOVER → CURATE → ADVISE**. For the composed flow diagram and
the ordered "run X, then run Y" setup runbook, go straight to
[`scientific_pipeline.md`](scientific_pipeline.md); this page is the map and the
invariants.

## What the pipeline does

| Stage | Capability | What it produces | Context / entry point | Deep dive |
|---|---|---|---|---|
| DISCOVER | Chemical identity resolution | Normalized `compounds` + `compound_identifiers` (MeSH/CID/ChEBI/CAS) | `Chemistry.Resolver` | [`chemistry.md`](chemistry.md) |
| DISCOVER | Literature crawl | `scientific_studies` (PMID-keyed), fanned to species/ingredients | `Literature` (Entrez) · `LiteratureCrawlWorker` | [`literature_discovery.md`](literature_discovery.md) |
| DISCOVER | Entity + relation extraction | `study_entity_mentions` + directional `study_entity_relations` | `Literature` (PubTator3) · `PubTatorAnnotationWorker` | [`pubtator.md`](pubtator.md) |
| DISCOVER | Qualitative compound facts | "Spinach contains Oxalate" (`Food.Compounds`) | `Food.Compounds` | [`food_compounds.md`](food_compounds.md) |
| DISCOVER | Quantitative measurements | "Spinach, Oxalate, Raw: 750 mg/100g" (immutable) | `Food.CompoundMeasurements` | [`compound_measurements.md`](compound_measurements.md) |
| — | Evidence summaries | Read-only mean/range/variance + auditable evidence score | `Food.EvidenceAggregation.summarize/2` | [`evidence_aggregation.md`](evidence_aggregation.md) |
| CURATE | Fact promotion | Scored `species_compound_candidates` → `species_compound_relationships` | `Food.CompoundCandidates` · `CompoundCandidateDerivationWorker` | [`compound_candidates.md`](compound_candidates.md) |
| ADVISE | Dietary recommendations | Conditions ↔ compounds ("Kidney Stones: avoid Oxalate") | `Mehungry.Health` · `RecommendationCandidateDerivationWorker` | [`health_recommendations.md`](health_recommendations.md) · [`pubtator_relations_recommendations.md`](pubtator_relations_recommendations.md) |

## External authorities & configuration

The pipeline discovers, it doesn't invent — every registry is normalized from an
outside source.

| Source | Normalized into | Adapter | Key |
|---|---|---|---|
| **USDA FDC** | `ingredients` (+ `FoundementalFoodSpecies` curation) | `FoodData.Usda.*` | `FDC_API_KEY` (required) |
| **NCBI PubMed (Entrez)** | `scientific_studies` | `Literature` / `entrez_responses` | NCBI E-utilities (keyless) |
| **NCBI PubTator3** | `study_entity_mentions`, `study_entity_relations` | `Literature` / `pubtator_responses` | keyless |
| **PubChem** | `compounds`, `compound_identifiers` | `Chemistry.Resolver` / `pubchem_responses` | keyless |

Full-text measurement extraction is done off-box by the local AI QA model and posted
back over the token-guarded `/api/local_ai/*` API — see
[`../ai/measurement_extraction.md`](../ai/measurement_extraction.md).

## Internal collaborators

Other parts of the project the pipeline leans on (integration surface / blast radius):

| Context | What the pipeline uses it for | Doc |
|---|---|---|
| **Food (core)** | Ingredients, `FoundementalFoodSpecies` (the `scientific_name` that drives the crawl), measurement units | [`../food/food.md`](../food/food.md) |
| **FoodData.Usda** | Seeding ingredients/species from USDA (`seed_imports` queue) | [`../food/food.md`](../food/food.md) |
| **AI — local QA model** | PMC full-text fetch + measurement-candidate extraction, posted back for review | [`../ai/measurement_extraction.md`](../ai/measurement_extraction.md) |
| **Accounts / admin** | Admin-gated review + curation UIs under `/professional/*` | [`../users/accounts.md`](../users/accounts.md) |
| **Oban** | The single-threaded `:imports` queue that drives crawl → annotate → derive | — |

## Where the code lives

- **`apps/mehungry/lib/mehungry/{chemistry,literature}/`** — the DISCOVER adapters
  (PubChem/NCBI) over the study + compound registries.
- **`apps/mehungry/lib/mehungry/food/`** — the compound fact layers
  (`Compounds`, `CompoundMeasurements`, `EvidenceAggregation`, `CompoundCandidates`)
  as a sidecar under the `Food` facade. **Facts only** — no advice here.
- **`apps/mehungry/lib/mehungry/health/`** — the ADVISE layer (conditions ↔ compounds).
- **`apps/mehungry/lib/mehungry/science/`** — pipeline orchestration:
  `PipelineWatchdog` (resumes a broken single-threaded run), `PipelineReset`,
  `RunReconciler`.
- Admin/curation UIs: `apps/mehungry_web/.../professional_live/` (`science_pipeline.ex`,
  `studies.ex`, `entities.ex`, plus `/professional/compound-candidates` and
  `/professional/health`).

## Cross-cutting principles

The invariants that keep the subsystem legible (elaborated in
[`scientific_pipeline.md`](scientific_pipeline.md)):

1. **Evidence never writes facts directly.** PubTator mentions and literature
   co-occurrence are *evidence*; only `Food.CompoundCandidates` writes
   `species_compound_relationships` facts.
2. **Facts, then advice — never mixed.** All `Food.*` compound layers are facts only;
   dietary guidance lives solely in `Mehungry.Health`, which reads those facts.
3. **Keyed on species, not ingredients.** Candidates and facts hinge on
   `FoundementalFoodSpecies` (via `scientific_name`); ingredients are derived
   *through* species at read time — there is no condition↔ingredient link.
4. **Everything is review-gated.** Strong candidates auto-promote over a threshold;
   otherwise an admin promotes/rejects. Literature-derived recommendations are
   **never** auto-promoted.
5. **Provenance is preserved.** Raw payloads (`entrez_/pubtator_/pubchem_responses`),
   reference-study links, and evidence scores keep every fact auditable back to source.
6. **The pipeline is a single-threaded chain.** Crawl → annotate → derive run one at a
   time on `:imports`; `PipelineWatchdog` resumes a run whose chain broke.

## Read next

- [`scientific_pipeline.md`](scientific_pipeline.md) — **start here**: the composed
  DISCOVER→CURATE→ADVISE flow and the ordered setup runbook.
- [`chemistry.md`](chemistry.md) — compound-identity resolution (PubChem/MeSH/ChEBI/CAS).
- [`literature_discovery.md`](literature_discovery.md) — the PubMed/Entrez crawl and study fan-out.
- [`pubtator.md`](pubtator.md) — PubTator3 entity + relation extraction.
- [`food_compounds.md`](food_compounds.md) — qualitative compound facts (`Food.Compounds`).
- [`compound_measurements.md`](compound_measurements.md) — immutable quantitative measurements.
- [`evidence_aggregation.md`](evidence_aggregation.md) — read-only evidence summaries + scores.
- [`compound_candidates.md`](compound_candidates.md) — the curation step that promotes evidence to facts.
- [`health_recommendations.md`](health_recommendations.md) — the advice layer (conditions ↔ compounds).
- [`pubtator_relations_recommendations.md`](pubtator_relations_recommendations.md) — literature relations → review-gated recommendations.

> Adjacent but not "science": the local AI QA model that does full-text measurement
> extraction is documented with the AI subsystem —
> [`../ai/measurement_extraction.md`](../ai/measurement_extraction.md). Recipe/meal
> generation is unrelated ([`../ai/ai.md`](../ai/ai.md)).
