# Food Compound Knowledge

A decoupled enrichment layer that represents **bioactive / chemical compounds** as
first-class reference entities and links them to existing ingredients as *scientific
facts* — with a relationship type, confidence score, and provenance.

> Examples: `Spinach` **contains** `Oxalate`; `Broccoli` **contains** `Sulforaphane`.

It never modifies the USDA ingestion pipeline or any existing table, and it stores
**only scientific facts** — never recommendations, limits, or dietary advice.

---

## 1. Why this exists

The existing enrichment layer (`Mehungry.Food.Enrichment`) can attach a flat
per-ingredient measure via `IngredientScientificProperty` (a `property_key → value`
pair, e.g. `total_polyphenols`). That is fine for scalar measurements but cannot model
a **compound as a shared entity** with its own chemical identity that many ingredients
reference.

This layer adds that: a normalized `Compound` registry (like `Nutrient`) plus a
join table of ingredient↔compound facts. That lets compounds be:

- deduplicated and referenced by a stable identity (PubChem CID, ChEBI ID, synonyms);
- linked to many ingredients with per-link provenance and confidence;
- queried both ways ("what compounds are in spinach?" / "what contains oxalate?").

**Constraints honored:**

- New Ecto schemas + one migration only — no existing table is altered.
- USDA ingestion/reconciliation is untouched; these tables are keyed by
  `ingredient_id`/`compound_id` and never read or written by the ingestion path.
- **Facts only.** No column encodes advice, a recommended limit, or a severity — `notes`
  is factual free text.
- Multiple facts per ingredient/compound pair are allowed (different `relationship_type`
  or `source`); the same fact from the same source is deduped, never duplicated.

---

## 2. Data model

Two new tables (migration
`priv/repo/migrations/20260725150000_create_food_compounds.exs`).

```
   compounds (registry)                 ingredient_compound_relationships (facts)
   ┌───────────────────────────┐        ┌──────────────────────────────────────┐
   │ name (unique)             │───────<│ compound_id                          │
   │ compound_type             │        │ ingredient_id ──> ingredients (exist) │
   │ pubchem_cid (unique)      │        │ relationship_type: contains|high_in|  │
   │ chebi_id                  │        │   low_in|trace|absent                 │
   │ synonyms  (text[])        │        │ confidence, source                    │
   │ identifiers (jsonb)       │        │ notes                                 │
   │ description               │        │ enrichment_source_id ──┐ (optional    │
   └───────────────────────────┘        └────────────────────────┴─ citation)   │
                                                                  v
                                             ingredient_enrichment_sources
                                             (reused citation registry)
```

### `compounds` — the registry
A shared reference entity, one row per compound. Keyed by `name`; its
cross-database identity lives in the normalized `compound_identifiers` table.

| Column | Meaning |
|---|---|
| `name` | Compound name, e.g. `"Oxalate"`, `"Sulforaphane"`. Required, unique. |
| `compound_type` | Class: `oxalate \| lectin \| phytate \| histamine \| polyphenol \| fodmap \| purine \| salicylate \| other`. Required. |
| `synonyms` | Alternate names (`text[]`, default `[]`). |
| `properties` | Structural descriptors as a `jsonb` map — `molecular_formula`, `smiles`, `isomeric_smiles`, `inchi`, `iupac_name`. Not identifiers (isomers share a formula). |
| `description` | Optional factual description. |

**Indexes:** `unique (name)`; `index (compound_type)`.

### `compound_identifiers` — normalized cross-database identity
One row per external identifier, so adopting a new chemical database never needs a
schema change. Written by `Mehungry.Chemistry.Resolver` (see `docs/chemistry.md`).

| Column | Meaning |
|---|---|
| `compound_id` | FK → `compounds` (`on_delete: delete_all`). |
| `namespace` | `mesh \| pubchem \| chebi \| cas \| hmdb \| wikidata \| inchikey \| foodb`. |
| `identifier` | The external id, e.g. `"D000082"`, `"971"`, `"CHEBI:16995"`. |
| `is_primary` | Marks the identifier the compound was seeded from. |
| `source` | Who asserted it: `pubchem \| pubtator \| chemistry \| manual`. |

**Indexes:** `unique (namespace, identifier)` — one compound per external id;
`index (compound_id)`.

### `ingredient_compound_relationships` — the facts
An ingredient↔compound link with provenance.

| Column | Meaning |
|---|---|
| `ingredient_id` | The existing USDA-backed ingredient (`on_delete: delete_all`). |
| `compound_id` | The compound (`on_delete: delete_all`). |
| `relationship_type` | `contains \| high_in \| low_in \| trace \| absent`. Default `contains`. |
| `confidence` | 0.0–1.0 score. |
| `source` | Provenance: `manual \| ai \| literature \| external_db`. |
| `notes` | Free-form **factual** note. |
| `enrichment_source_id` | Optional citation into `ingredient_enrichment_sources` (`on_delete: nilify_all`). |

**Indexes:** `unique (ingredient_id, compound_id, relationship_type, source)` — the
never-overwrite natural key; `index (compound_id)`; `index (enrichment_source_id)`.

Because the unique key includes `relationship_type` and `source`, the same pairing can
be recorded as `contains` from `literature` **and** `high_in` from `ai` as two distinct
facts, while re-asserting an identical fact is an idempotent upsert.

---

## 3. Context API (`Mehungry.Food.Compounds`, via the `Mehungry.Food` facade)

**Registry**

```elixir
Food.create_compound(attrs)                # strict insert
Food.upsert_compound(attrs)                # find-or-create on name → {:ok, compound}
Food.get_compound!(id)
Food.get_compound_by_name(name)
Food.list_compounds()                      # alphabetical
Food.list_compounds_by_type("polyphenol")
```

**Facts**

```elixir
Food.link_compound(attrs)                  # strict insert of a relationship
Food.upsert_compound_relationship(attrs)   # idempotent on the natural key
Food.delete_compound_relationship(rel)
Food.list_compounds_for_ingredient(ing_id)  # [%Compound{}]
Food.list_ingredients_for_compound(cmp_id)  # [%Ingredient{}]
Food.list_compound_relationships(ing_id)     # raw rows, compound preloaded
```

**Ergonomic one-call fact** — upserts the compound, then upserts the link:

```elixir
Food.add_compound_to_ingredient(
  spinach.id,
  %{name: "Oxalate", compound_type: "oxalate", pubchem_cid: 971},
  %{relationship_type: "contains", source: "literature", confidence: 0.95}
)
```

`upsert_compound/1` and `upsert_compound_relationship/1` are find-or-create /
`on_conflict` upserts on the natural keys, mirroring `Mehungry.Food.Enrichment`.

---

## 4. Facts only — the hard boundary

This layer deliberately has **no** column for a recommended intake, a threshold, a
"avoid if condition X" flag, or a severity. It records *what is scientifically true*
about a compound and its presence in an ingredient. Any user-facing guidance
(recommendations, dietary rules) belongs in a separate layer that *reads* these facts —
never here.

**How relationships get here.** A relationship is never asserted directly from raw
evidence (PubTator mentions, literature co-occurrence). The curation step
`Food.CompoundCandidates` (**`docs/compound_candidates.md`**) derives scored *candidates*
from that evidence and promotes the strong ones — automatically over a config threshold or
by admin review — writing curated rows here via `upsert_compound_relationship/1`.

---

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Food.Compounds` | `food/compounds.ex` | Context: registry CRUD, identifier CRUD, fact CRUD, both-way queries. |
| `Food.Compound` | `food/schemas/compound.ex` | Compound registry schema. |
| `Food.CompoundIdentifier` | `food/schemas/compound_identifier.ex` | Normalized `(namespace, identifier)` identity row. |
| `Food.IngredientCompoundRelationship` | `food/schemas/ingredient_compound_relationship.ex` | Ingredient↔compound fact schema. |

The `Ingredient` schema gains read-only `has_many :compound_relationships` and
`has_many :compounds, through:` associations (not in `cast_assoc` — writes go only
through `Food.Compounds`). All public functions are exposed via the `Mehungry.Food`
facade.

---

## 6. Testing

`apps/mehungry/test/mehungry/food/compounds_test.exs` covers the registry (create,
name dedupe, `pubchem_cid` uniqueness, `synonyms`/`identifiers` round-trip, type
filtering, enum validation) and the facts (both worked examples, both-way listing,
never-overwrite vs. distinct-fact behavior, enum validation).

```bash
mix test apps/mehungry/test/mehungry/food/compounds_test.exs
```

---

## 7. Automated population — the Chemistry context

The compound registry is populated automatically by the **`Mehungry.Chemistry`**
context (see **`docs/chemistry.md`**), whose `Chemistry.Resolver` is the
identifier-first ingestion entry point. Given an external identifier (e.g. a MeSH
id from PubTator) or a fuzzy name, it resolves a stable identity and syncs it in —
deduped by `(namespace, identifier)`, cross-references (PubChem CID, ChEBI, CAS,
InChIKey) written as `compound_identifiers` rows, structural descriptors in
`properties`, provenance in `compound_sources`, and the raw payload retained in
`pubchem_responses`. It writes through `Food.Compounds.upsert_compound_identifier/1`
and `upsert_compound/1`. The rest of the app still reads only `Food.Compounds`.

## 8. Out of scope / follow-ons

- No Oban worker or progress-run tracker (unlike the literature crawl in
  `docs/literature_discovery.md`) — the registry is a plain layer like
  `Enrichment`, and PubChem population (`Chemistry`) is synchronous.
- Additional external sources (FooDB, ChEBI, HMDB) reuse the `compound_sources`
  provenance layer and the `upsert_compound_by_cid/1` seam.
