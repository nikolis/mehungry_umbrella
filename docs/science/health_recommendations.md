# Health Recommendations

A **health-recommendation knowledge model**: it represents health conditions as
first-class reference entities and links them to bioactive **compounds** as dietary
recommendations — *"Kidney Stones: avoid Oxalate"*, *"IBS: limit FODMAP"*.

> Kidney Stones **has concern** Oxalate — and (separately) Oxalate **is contained
> in** Spinach.

This is the **advice** layer that the "facts only" compound stack deliberately
defers to (`docs/science/food_compounds.md` §4: *"Any user-facing guidance
(recommendations, dietary rules) belongs in a separate layer that reads these
facts — never here."*). It is a top-level `Mehungry.Health` context, a sibling of
`Food` / `Chemistry` / `Literature`.

```
   conditions ──has concern──▶ compound_recommendations ──▶ compounds
   (Mehungry.Health)          (avoid | limit | …)          (Food.Compounds)
                                                              │
                                        species_compound_relationships
                                        ("Oxalate is contained in Spinach")
                                                              │
                                                          ingredients
```

---

## 1. The hard rule — conditions never reference ingredients

A condition references a **compound**, never an ingredient. There is no
`ingredient_id` anywhere in this layer. The food a patient should avoid is
**derived** by composing this layer with the existing
`SpeciesCompoundRelationship` facts through the shared compound — at read time,
in `ingredients_for_condition/2`. The schemas stay fully decoupled from ingredient
data, so USDA ingestion and the food-facts layer are untouched.

This mirrors the existing cross-context precedent: `Literature.StudyCompound` also
FK-references `Food.Compound` without coupling the two contexts' schemas.

---

## 2. Data model — one migration

`priv/repo/migrations/20260731120000_create_health_recommendations.exs`.

### `conditions` — the condition registry
A shared reference entity, one row per condition (like `compounds`).

| Column | Meaning |
|---|---|
| `name` | e.g. `"Kidney Stones"`, `"IBS"`. Required, **unique**. |
| `synonyms` | `text[]`, default `[]` — abbreviations/aliases (`"Irritable Bowel Syndrome"`). |
| `category` | Optional grouping (`Endocrine`, `Digestive`, `Renal`). |
| `subcategory` | Optional finer grouping under `category` (`Endocrine → Diabetes`, `Digestive → Liver Disease`). Added `20260811120000`. |
| `description` | Optional factual description. |

**Indexes:** `unique (name)`; `index (category)`; `index (subcategory)`.

### Bulk seed — the condition catalogue
`Mehungry.Health.ConditionSeeder.seed/1` idempotently loads the ~193-condition
reference registry from `priv/repo/seeds/data/health_conditions.json` (one object
per condition: `main_name`/`synonyms`/`category`/`subcategory`/`description`),
upserting on the unique `name` (`on_conflict: :replace`, so re-seeding refreshes
edits without duplicates). Wired into `priv/repo/seeds.exs`, so `mix ecto.reset`
loads it; also runnable standalone. Seeds **conditions only** — no
`CompoundRecommendation` advice (that stays curated, since it needs a resolved
compound).

### `compound_recommendations` — the advice facts
A condition↔compound recommendation with provenance. **No ingredient reference.**

| Column | Meaning |
|---|---|
| `condition_id` | FK → `conditions` (`on_delete: delete_all`). |
| `compound_id` | FK → `compounds` (`on_delete: delete_all`). |
| `recommendation` | `avoid \| limit \| caution \| encourage \| monitor`. Required. |
| `severity` | `low \| moderate \| high \| severe`. Optional. |
| `evidence_level` | `strong \| moderate \| limited \| insufficient` — reuses the `Food.EvidenceAggregation` labels. Optional. |
| `source` | Provenance: `manual \| ai \| literature \| guideline`. Required. |
| `source_reference` | `map` — structured citation for non-PubMed advice: `%{"label","url","doi","pmid"}`. |
| `notes` | Free-form factual note (e.g. *"applies to high-FODMAP foods"*). |

**Natural key** (unique): `(condition_id, compound_id, source)` — one recommendation
per condition/compound per source. Re-asserting from the same source is an
idempotent upsert (a correction); a different source is a distinct row — so a
`guideline` recommendation and an `ai` one coexist.

**Indexes:** unique `(condition_id, compound_id, source)`; `index (compound_id)`;
`index (condition_id)`.

#### Frozen PubMed provenance — the citation shown to the user
Every user-facing conclusion must cite the paper(s) behind it (it doubles as the
disclaimer). PubMed studies (`scientific_studies`, PMID-keyed) are the primary source,
so the link is carried through to the result — not left on the mutable candidate:

- **`compound_recommendation_studies`** (`recommendation_id` → `study_id`, unique per
  pair) is the recommendation's reference-study join, exposed as the `:studies`
  `has_many :through`. It is **written once, at promotion**, by copying the backing
  `CompoundRecommendationCandidate`'s studies (`RecommendationCandidates.promote_candidate`),
  and — unlike the candidate's `*_candidate_studies`, which are refreshed on every
  re-derivation — **re-derivation never touches it**. So the recommendation keeps citing
  exactly the papers the human validated. (The species-fact half of the "why this food"
  chain has the mirror table `species_compound_relationship_studies`, frozen the same way
  at `CompoundCandidates.promote_candidate`.)
- **Citation invariant (changeset-enforced):** a `manual`/`guideline` recommendation
  carries no PubMed study, so it **must** supply a non-empty `source_reference`; the
  `CompoundRecommendation` changeset rejects it otherwise. `literature`/`ai` sources are
  exempt (their citation comes from the frozen study links).
- **Read → UI:** `recommendations_for_condition/2` and `recommendations_for_compound/1`
  preload `:studies`; `species_for_condition/2` / `recommendations_for_species/1`
  batch-attach `:recommendation_citations` + `:fact_citations`. The public condition
  page links each conclusion to `pubmed.ncbi.nlm.nih.gov/<pmid>` (or the structured
  `source_reference`) under a "not medical advice — read the source" disclaimer.

---

## 3. Context API (`Mehungry.Health`)

**Condition registry**

```elixir
Health.create_condition(attrs)               # strict insert
Health.upsert_condition(attrs)               # find-or-create on name → {:ok, condition}
Health.get_condition!(id)
Health.get_condition_by_name(name)
Health.list_conditions()                     # alphabetical
Health.list_conditions_by_category("renal")
```

**Recommendation facts**

```elixir
Health.create_recommendation(attrs)          # strict insert
Health.upsert_recommendation(attrs)          # idempotent on (condition, compound, source)
Health.delete_recommendation(rec)
Health.recommendations_for_condition(cond_id)  # rows, :compound + frozen :studies preloaded
Health.recommendations_for_compound(cmp_id)    # rows, :condition + frozen :studies preloaded
```

**Ergonomic one-call recommendation** — upserts the condition, then upserts the
link against an existing compound:

```elixir
Health.add_recommendation(
  %{name: "Kidney Stones", category: "renal"},
  oxalate.id,
  %{recommendation: "avoid", severity: "high", evidence_level: "strong", source: "guideline"}
)
# or against a known condition id:
Health.add_recommendation(kidney.id, oxalate.id, %{recommendation: "avoid", source: "guideline"})
```

**Derived cross-layer read** — the payoff of the decoupling:

```elixir
# Primary read → the implicated FoundementalFoodSpecies.
Health.species_for_condition(kidney.id, :avoid)
#=> [%{species: %FoundementalFoodSpecies{name: "Spinach"}, compound: %Compound{name: "Oxalate"},
#      recommendation: "avoid", severity: "high", evidence_level: "strong"}]

# Convenience → the ingredients, derived STRICTLY through those species.
Health.ingredients_for_condition(kidney.id, :avoid)
#=> [%{ingredient: %Ingredient{name: "spinach"}, compound: %Compound{name: "Oxalate"}, ...}]
```

`species_for_condition/2` joins `condition → compound_recommendations → compounds →
species_compound_relationships → species` at read time;
`ingredients_for_condition/2` extends it one hop `→ foundemental_foods → ingredients`.
There is no condition↔ingredient or fact↔ingredient link. Pass a recommendation
(`"avoid"` / `:avoid`) to filter, or omit for every recommendation.

---

## 4. Advice, not facts — the boundary (inverse of `food_compounds.md`)

Where `Food.Compounds` stores **only scientific facts** and forbids advice, this
layer is exactly where advice belongs: `recommendation` and `severity` express
guidance. It reads the compound registry and the ingredient↔compound facts but
never writes them, and it never asserts a new scientific fact.

---

## 4b. The nutrient recommendation layer (sibling of the compound one)

A condition can also link to **nutrients**, not just compounds —
`Health.NutrientRecommendation` (`nutrient_recommendations`) mirrors
`CompoundRecommendation` field-for-field (`recommendation` `avoid|limit|caution|
encourage|monitor`, `severity`, `evidence_level`, `source`, `source_reference`,
same citation guard) but references a nutrient by its **canonical name string**
(`nutrient_name`), never an FK — the same nutrient name exists under several units
(`nutrients` is unique on `[name, measurement_unit_id]`), and this matches how
blueprints store nutrient tags.

The two layers are complementary by design. The compound layer resolves to foods
through `SpeciesCompoundRelationship` **facts, which are pipeline-derived and often
empty**; the nutrient layer resolves through the **populated** per-100g USDA
`IngredientNutrient` table, so it produces real foods out of the box:

```
   conditions ──▶ nutrient_recommendations ──▶ (canonical nutrient name)
   (Mehungry.Health)  (encourage | limit | …)          │
                                          Health.NutrientTargets
                          (label → matching Nutrient rows + per-100g threshold)
                                                        │
                                        ingredient_nutrients (amount ≥ threshold)
                                                        │
                                              ingredients → recipes / species
```

`Health.NutrientTargets` (`health/nutrient_targets.ex`) is the resolver: it maps a
canonical label (`"Omega-3"`, `"Fiber"`, `"Saturated Fat"`, …) to the raw USDA
`Nutrient` rows via `Food.NutrientNameNormalizer`, plus the per-100g threshold that
classifies a food as "high in" it (reusing `Food.NutrientInteractions`'s
"significant" values where they exist). Ids are cached in `:health_cache`.

**Read seams in `Health` (nutrient siblings of the compound ones):**
`nutrient_recommendations_for_condition/1`,
`encouraged/discouraged_nutrient_names_for_conditions/1`,
`encouraged_species_ids_for_conditions/1` (the `/foods` filter),
`nutrient_encouraged_recipe_ids_query/1` (unioned into
`recipes_prioritized_for_conditions_query/1`), and nutrient-derived badges merged
into `flags_for_recipes/2` / `flags_for_ingredients/2` (flags carry
`kind: :nutrient` + a `:label` instead of a `:compound` struct). The presentation
gate `list_conditions_for_presentation/1` shows a condition backed by **either**
engine.

The shipped **"Anti-Inflammatory"** indication (seeded in `seeds.exs`,
`category: "dietary_pattern"`) is the first consumer: encourage
Polyphenols/Flavonoids (compounds) + Omega-3/Fiber/MUFA/Vit C/E (nutrients), limit
Saturated Fat/Added Sugar/Sodium — every downstream surface (recipe/foods search,
badges, blueprint auto-suggest) reads it generically. Curated at
`/professional/health` next to the compound form.

---

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Health` | `health.ex` | Context: condition registry, recommendation CRUD, derived composition read. |
| `Health.Condition` | `health/condition.ex` | Condition registry schema. |
| `Health.ConditionSeeder` | `health/condition_seeder.ex` | Idempotent bulk seed of the condition registry from the bundled JSON catalogue. |
| — | `priv/repo/seeds/data/health_conditions.json` | ~193-condition source catalogue. |
| `Health.CompoundRecommendation` | `health/compound_recommendation.ex` | Condition↔compound recommendation schema (+ `source_reference`, frozen `:studies`, citation guard). |
| `Health.NutrientRecommendation` | `health/nutrient_recommendation.ex` | Condition↔nutrient recommendation schema (name-keyed sibling of the compound one). |
| `Health.NutrientTargets` | `health/nutrient_targets.ex` | Canonical nutrient label → USDA `Nutrient` rows + per-100g threshold; resolves nutrient advice to foods. |
| — | `priv/repo/migrations/20260923120000_create_nutrient_recommendations.exs` | `nutrient_recommendations` table + natural-key unique index. |
| `Health.CompoundRecommendationStudy` | `health/compound_recommendation_study.ex` | Frozen PubMed-provenance join (recommendation ↔ study), copied once at promotion. |
| — | `priv/repo/migrations/20260731120000_create_health_recommendations.exs` | Both tables + natural-key unique index. |
| — | `priv/repo/migrations/20260922000001_create_compound_recommendation_studies.exs` · `…000003_add_source_reference_to_compound_recommendations.exs` · `…000004_backfill_result_study_provenance.exs` | Frozen provenance table, `source_reference` column, one-time backfill from promoted candidates. |

`Food.Compound` gains a read-only `has_many :condition_recommendations` (written
only via `Mehungry.Health`, not in `cast_assoc`).

---

## 6. Testing

`apps/mehungry/test/mehungry/health_test.exs` covers the condition registry
(create, name dedupe/uniqueness, synonyms/category round-trip, category filtering),
the recommendations (the *Kidney Stones → avoid → Oxalate* and *IBS → limit →
FODMAP* worked examples, both-way listing, enum + required-field validation,
idempotent upsert vs. distinct-source rows), and the derived read proving Spinach
surfaces for Kidney Stones **without** any condition→ingredient FK.

```bash
mix ecto.migrate
mix test apps/mehungry/test/mehungry/health_test.exs
```

---

## 7. Out of scope / follow-ons

- **Literature-derived recommendations — BUILT.** Recommendations no longer have to be
  hand-entered: `Health.RecommendationCandidates` (mirroring `Food.CompoundCandidates`)
  aggregates PubTator's directional chemical↔disease relations
  (`Literature.StudyEntityRelation`) into scored, **review-gated**
  `CompoundRecommendationCandidate`s. Relation valence maps to a *suggested* direction
  (negative-correlation → `encourage`, positive → `avoid`, association → neutral); an
  admin confirms direction + severity at `/professional/health` to promote into a
  `CompoundRecommendation` (`source: "literature"`, conservative default
  `evidence_level`). Nothing is auto-promoted. Diseases resolve to conditions via
  `Health.ConditionResolver` + `condition_identifiers`. Derivation runs as an Oban stage
  (`RecommendationCandidateDerivationWorker`) surfaced on `/professional/science`.
  See `docs/science/pubtator_relations_recommendations.md`.
- **Disease-seeded crawl + phase-aware recommendations — BUILT** (2026-09-23). The
  Phase-2 reverse crawl (discover literature *per condition*) now exists, plus a
  separate **phase-aware** extraction pipeline: a per-condition `condition_states`
  registry (Active Flare vs Remission …), an offline Python extractor that reads study
  prose (PubTator relations are state-blind) and posts review-gated, state-tagged
  candidates, and a **decoupled** `condition_state_recommendations` store surfaced on the
  condition page's phase selector. See **`docs/science/condition_phase_recommendations.md`**.
- **Per-condition search + batch analysis from `/professional/health` — BUILT.** Each
  condition card has a **"Search papers"** button that runs the reverse crawl for that one
  condition on demand (`Literature.crawl_condition/2`, async via `start_async`), associates
  the discovered studies (`study_conditions`), and lists them in a collapse/expand panel.
  The panel is **permanent**: `load/0` rebuilds it from the DB every render via
  `Literature.studies_by_condition/1` (one grouped query), so a condition's associated papers
  show underneath it on page load, not just right after a crawl. Admin ticks papers
  (up to 200; a **Select all** button checks them in one go) → **"Analyze selected"**
  POSTs their PMIDs to the external `mehungry_extractor`
  batch-analysis service (`POST /analyze`, deterministic evidence engine — see
  `mehungry_extractor/docs/api.md`) via `Mehungry.Extractor.Client` (behaviour-seamed on the
  `:extractor_client` config key; base URL `:extractor_base_url` / `EXTRACTOR_BASE_URL`,
  default `http://127.0.0.1:8000`). The synthesized conclusions/outliers/warnings render
  read-only in a modal — a first step; nothing is promoted or persisted from the result yet.
- The registry+facts CRUD itself remains a plain synchronous layer (no cache/config seam).
- **Evidence integration.** `evidence_level` is entered by the source today; wiring
  it to `Food.summarize/2` (so a recommendation's strength tracks the measured
  evidence for its compound in linked foods) is a natural follow-on.
- **Per-preparation nuance.** A recommendation is compound-level; refining "avoid
  raw spinach but boiled is fine" would compose with the measurement/preparation
  data (`docs/science/compound_measurements.md`).
