# PubTator3 relations → condition recommendations (PROPOSED — not implemented)

**Status:** design note / backlog. Nothing here is built yet. Captured after an
empirical spike on 2026-08-01.

## Why

`Mehungry.Health` recommendations (`condition → compound → avoid|limit|encourage`)
are currently hand-curated (via `/professional/health` or `Health.add_recommendation/3`).
We want to **derive candidate recommendations from the literature we already crawl**.
The blocker identified earlier was *direction/valence*: co-occurrence tells you a
compound is *studied with* a condition, not whether to avoid or encourage it.

## Empirical finding (the reason this is worth doing)

PubTator3's BioC-JSON response includes a per-document **`relations`** array that we
already download and store in `pubtator_responses.raw_json`, but our
`Literature.PubTator.Client.parse_biocjson/1` only reads `passages[].annotations`
(entity mentions) — **it discards the relations.**

Sampling the stored payloads (small annotated corpus) found **36 relations**:

| relation `type` | count | | entity pair (`biotype1 ↔ biotype2`) | count |
|---|---|---|---|---|
| Negative_Correlation | 19 | | chemical ↔ disease | **21** |
| Association | 11 | | chemical ↔ chemical | 11 |
| Positive_Correlation | 6 | | chemical ↔ gene | 3 |
| | | | disease ↔ gene | 1 |
| | | | **chemical ↔ species** | **0** |

Each relation carries a `score` and the two entities with their MeSH ids, e.g.:

> **Flavonoids —`Negative_Correlation`→ Inflammation** (score 0.9989)

Two conclusions:

1. **Does NOT help "chemicals contained in a species."** PubTator3 extracts no
   chemical↔species(organism) relations and has no "contained-in-food" type. For
   `FoundementalFoodSpecies` composition, stick with co-occurrence + measurements
   (`docs/compound_measurements.md`, `docs/evidence_aggregation.md`).
2. **Directly solves the direction problem for condition recommendations.** The
   chemical↔disease relations are directional and already on disk:
   - `Negative_Correlation` → compound inversely associated with the condition → lean **encourage**
   - `Positive_Correlation` → lean **avoid / limit**
   - `Association` → neutral (leave direction for review)

## Proposed slice (cheap, reuses existing data — no new crawling)

1. **Parse relations** — extend `parse_biocjson/1` (`literature/pubtator/client.ex`)
   to also return each document's `relations` (type, score, the two entities'
   `type`/`identifier`).
2. **Persist** — new `study_entity_relations` table:
   `study_id`, `type`, `score`, `entity1_type`/`entity1_identifier`,
   `entity2_type`/`entity2_identifier`, and resolved FKs where possible
   (`compound_id` via `Chemistry.Resolver`, `condition_id` via a disease→condition
   resolver — see `docs/pubtator.md` for the chemical-resolution pattern to mirror).
3. **Re-mine** — a one-off pass over existing `pubtator_responses.raw_json` so we get
   value from the corpus already annotated (no re-fetch), plus wire it into
   `PubTator.annotate_study/2` going forward.
4. **Recommendation candidates** — a `CompoundRecommendationCandidate` layer mirroring
   `Food.CompoundCandidates`: aggregate compound↔condition relations (blend score +
   count), map relation type → suggested direction, cite reference PMIDs, and queue
   for admin promotion into `Health.CompoundRecommendation` on `/professional/health`.

## Reuse

- `Literature.PubTator.Client.parse_biocjson/1` + `pubtator_responses` (raw payloads).
- `Chemistry.Resolver` (chemical MeSH → compound) — already used for chemical mentions.
- The candidate → review → promote pattern (`Food.CompoundCandidates`,
  `SpeciesCompoundCandidateStudy` provenance, the `/professional/health` admin page).

## Safety stance

PubMed relation extraction is weak grounds for medical dietary advice. Everything
stays **review-gated candidates** (never auto-promoted), `source: "literature"` (not
`"guideline"`), low default `evidence_level`, neutral default direction for
`Association` until a human confirms.

## Related

- Condition discovery ("search 'Leaky gut' → resolve to MeSH → crawl → recommend"):
  the disease-driven crawl + condition resolver sketched in chat; this relations pass
  is the precursor that makes the *direction* signal available.
