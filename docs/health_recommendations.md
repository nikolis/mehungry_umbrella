# Health Recommendations

A **health-recommendation knowledge model**: it represents health conditions as
first-class reference entities and links them to bioactive **compounds** as dietary
recommendations — *"Kidney Stones: avoid Oxalate"*, *"IBS: limit FODMAP"*.

> Kidney Stones **has concern** Oxalate — and (separately) Oxalate **is contained
> in** Spinach.

This is the **advice** layer that the "facts only" compound stack deliberately
defers to (`docs/food_compounds.md` §4: *"Any user-facing guidance
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
| `notes` | Free-form factual note (e.g. *"applies to high-FODMAP foods"*). |

**Natural key** (unique): `(condition_id, compound_id, source)` — one recommendation
per condition/compound per source. Re-asserting from the same source is an
idempotent upsert (a correction); a different source is a distinct row — so a
`guideline` recommendation and an `ai` one coexist.

**Indexes:** unique `(condition_id, compound_id, source)`; `index (compound_id)`;
`index (condition_id)`.

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
Health.recommendations_for_condition(cond_id)  # rows, :compound preloaded
Health.recommendations_for_compound(cmp_id)    # rows, :condition preloaded
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

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Health` | `health.ex` | Context: condition registry, recommendation CRUD, derived composition read. |
| `Health.Condition` | `health/condition.ex` | Condition registry schema. |
| `Health.ConditionSeeder` | `health/condition_seeder.ex` | Idempotent bulk seed of the condition registry from the bundled JSON catalogue. |
| — | `priv/repo/seeds/data/health_conditions.json` | ~193-condition source catalogue. |
| `Health.CompoundRecommendation` | `health/compound_recommendation.ex` | Condition↔compound recommendation schema. |
| — | `priv/repo/migrations/20260731120000_create_health_recommendations.exs` | Both tables + natural-key unique index. |

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
  See `docs/pubtator_relations_recommendations.md`. The **disease-seeded crawl** (Phase 2 —
  discovering *new* literature per condition) is still backlog.
- The registry+facts CRUD itself remains a plain synchronous layer (no cache/config seam).
- **Evidence integration.** `evidence_level` is entered by the source today; wiring
  it to `Food.summarize/2` (so a recommendation's strength tracks the measured
  evidence for its compound in linked foods) is a natural follow-on.
- **Per-preparation nuance.** A recommendation is compound-level; refining "avoid
  raw spinach but boiled is fine" would compose with the measurement/preparation
  data (`docs/compound_measurements.md`).
