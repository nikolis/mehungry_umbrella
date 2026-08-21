# Glycemic Index import

> **Provenance pivot in progress.** The compiled 2021 International Tables are **not
> licensable for commercial use**, so the source of truth is moving from the *table*
> to the *primary studies it cites* (re-derived through the literature pipeline). The
> table's PDF is retained only as an internal verification oracle. Legal rationale and
> what changes in the code: **[`glycemic_index_licensing.md`](glycemic_index_licensing.md)**.
> Sections below still describe the original compilation-ingest model.

A **measured-value** import pipeline that attaches published Glycemic Index (GI)
values to our foods. Unlike the compound/health pipelines (which *derive* facts from
literature evidence), GI is **not computable** from the nutrient data we store — the
variable that sets GI is carbohydrate *structure*, absent from any composition table.
So this layer ingests authoritative measured values and connects them to our data
under the same **review gate** the rest of `docs/science/` uses.

Source: **International Tables of Glycemic Index and Glycemic Load Values 2021**
(Atkinson, Brand-Miller, Foster-Powell, Buyken, Goletzke; *AJCN*,
[doi:10.1093/ajcn/nqab233](https://doi.org/10.1093/ajcn/nqab233)) — Supplemental
Table 1 (~2100 ISO-26642-method, high quality) and Table 2 (~1900 lower quality).

```
priv/data/glycemic_index/*.csv  (user-supplied export)
   │  TableParser.parse  +  Food.ingest_glycemic_csv / mix gi.ingest
   ▼
glycemic_index_records            ── immutable published values (quality_tier: table1|table2)
   │  GlycemicIndexMatchWorker (:imports, 100/batch, self-re-enqueue chain, live progress)
   │    match each record → best FoundementalFoodSpecies, score match_confidence
   ▼
glycemic_index_candidates  (pending | promoted | rejected)
   │            ├─ auto-promote  (quality_tier=table1 AND matched_via=exact_name) ─┐
   │  admin Promote / Reject / Undo / species-override  (/professional/glycemic-index)
   ▼                                                                               ▼
IngredientScientificProperty(property_key:"glycemic_index", source:"external_db",
   value=gi, basis="glucose=100", reviewed:true) — fanned out to every ingredient
   of the matched species (Enrichment.upsert_scientific_property/1)
```

## Why a candidate layer

The *value* is authoritative, but the *match* of a table food ("Apples, raw") to one
of our `FoundementalFoodSpecies` is not. So a `GlycemicIndexCandidate` stages the
proposed match, scored by **name-match confidence** (not evidence strength), and never
becomes a fact until reviewed. This mirrors `Food.CompoundCandidates`.

## Matching (`Food.GlycemicIndex.match_record/2`)

Each record is matched against a snapshot of every species (`normalized_species/0`)
using `Ingredient.normalize_string/1` on the species name and the **head** of the food
item (segment before the first comma/paren):

| Tier | Rule | `matched_via` | confidence |
|---|---|---|---|
| Exact | normalized species name == food-item head/full (or `alternative_name`) | `exact_name` | 1.0 |
| Fuzzy | best `String.jaro_distance` ≥ `@min_similarity` (0.82) | `trigram` | the similarity |
| None | below threshold | — | no candidate created |

**Auto-promotion is deliberately narrow:** only `quality_tier == "table1"` **and**
`matched_via == "exact_name"`. Every fuzzy match and all of Table 2 wait for admin
review — a wrong match writes a wrong health number, so the bar is high.

## Promotion / Undo (fan-out)

Promotion resolves the species' ingredients via
`FoundementalFoods.list_ingredient_ids_for_species/1` and writes one reviewed
`IngredientScientificProperty(property_key: "glycemic_index", source: "external_db",
basis: "glucose=100")` per ingredient (idempotent on `(ingredient_id, property_key,
source)`), recording their ids in `candidate.promoted_property_ids`. **Undo** deletes
exactly those rows and marks the candidate `rejected` so a re-match won't re-promote.
A species with no curated ingredients yields `{:error, :no_ingredients}` and stays
pending. Re-matching never touches a `promoted`/`rejected` candidate.

## Usage

```bash
# 1. Drop the CSV export(s) in priv/data/glycemic_index/ (…table2.csv → Table 2 tier)
mix gi.ingest apps/mehungry/priv/data/glycemic_index/table1.csv
# 2. Match + review at /professional/glycemic-index (or Food.enqueue_glycemic_matching/0)
```

The parser (`FoodData.GlycemicIndex.TableParser`) is **column-name driven and
tolerant** — headers are normalized and looked up in `@header_aliases`; a combined
`"GI ± SEM"` cell is split, `reference_food` reduced to `glucose`/`bread`, and bold
**category** headings are carried down onto each data row. Add header aliases there if
an export words a column differently.

## Module map

| Module | File | Role |
|---|---|---|
| `Food.GlycemicIndex` | `food/glycemic_index.ex` | ingest, match/score, promote/reject/undo, queries, `enqueue_glycemic_matching/0` |
| `Food.GlycemicIndexRecord` / `…Candidate` / `…MatchRun` | `food/schemas/glycemic_index_*.ex` | source value / staged match / run tracker |
| `Food.GlycemicIndexMatchRuns` | `food/glycemic_index_match_runs.ex` | run lifecycle + PubSub (`"glycemic_index_match_runs"`) |
| `ObanWorkers.GlycemicIndexMatchWorker` | `oban_workers/glycemic_index_match_worker.ex` | batch-chain matcher (`:imports`) |
| `FoodData.GlycemicIndex.TableParser` | `food_data/glycemic_index/table_parser.ex` | CSV → record maps |
| `MehungryWeb.ProfessionalLive.GlycemicIndex` | `.../professional_live/glycemic_index.{ex,html.heex}` | admin match/review UI |

Public functions are exposed on the `Mehungry.Food` facade under distinct
`*_glycemic_*` names (e.g. `promote_glycemic_candidate/1`) so they don't collide with
the compound pipeline's same-shaped functions.

## Out of scope

No composition-based GI *computation* (unreliable estimates were rejected). Glycemic
**load** (`GI/100 × available_carb`) is computable from GI + existing nutrients but is a
separate follow-on. See the conversation history / plan for the reliability analysis.

## Testing

```bash
mix test apps/mehungry/test/mehungry/food/glycemic_index_test.exs \
         apps/mehungry/test/mehungry/oban_workers/glycemic_index_match_worker_test.exs \
         apps/mehungry_web/test/mehungry_web/live/professional_live/glycemic_index_test.exs
```
