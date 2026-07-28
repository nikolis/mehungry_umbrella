# Compound Measurements

A quantitative measurement layer over the compound registry: it records the
**numbers a research paper reports** for a compound in an ingredient, each as an
immutable, per-study observation.

> Example: *Spinach*, *Oxalate*, *Raw* — **750 mg/100g** (from one study).

It never modifies the USDA ingestion pipeline or any existing table, and it stores
**only scientific facts** — never recommendations, limits, or dietary advice.

```
   compounds (registry)         ── qualitative ──▶ ingredient_compound_relationships
   Food.Compounds               ("Spinach contains Oxalate")   (docs/food_compounds.md)
        │
        └── quantitative ──▶ compound_measurements                          ← this doc
            ("Spinach, Oxalate, Raw: 750 mg/100g", from study PMID …)
```

Where the qualitative layer answers *"does spinach contain oxalate?"*, this layer
answers *"how much, prepared how, measured how, reported by which paper?"*.

---

## 1. Why this exists

`IngredientCompoundRelationship` (`docs/food_compounds.md`) records **qualitative**
facts with a relationship type (`contains`, `high_in`, `low_in`, `trace`, `absent`)
and a confidence — but it cannot hold a *number* from a *specific paper*. There was
no place for the quantitative observation itself: `750 mg/100g` of oxalate in raw
spinach as measured by one study.

This layer adds that, as a first-class immutable fact keyed to the paper that
reported it. Many measurements accumulate per `(ingredient, compound)` across
studies and preparations; summarizing them (mean, range, per-preparation) is a
separate read-only concern.

**Constraints honored:**

- One new Ecto schema + one migration only — no existing table is altered.
- USDA ingestion/reconciliation is untouched; the table is keyed by
  `ingredient_id`/`compound_id` and never read or written by the ingestion path.
- **Facts only.** A measurement is a reported observation. No column encodes a
  recommended intake, threshold, or severity.
- **Immutable.** Historical values are never updated (see §4).

---

## 2. Data model

One new table (migration
`priv/repo/migrations/20260730120000_create_compound_measurements.exs`).

### `compound_measurements` — the observations

| Column | Meaning |
|---|---|
| `ingredient_id` | The existing USDA-backed ingredient (`on_delete: delete_all`). |
| `compound_id` | The compound (`on_delete: delete_all`). |
| `study_id` | Optional FK → `scientific_studies` (`on_delete: nilify_all`) — the paper that reported the value. |
| `value` | The measured quantity, e.g. `750.0`. Required, `>= 0`. |
| `unit` | The unit as reported, e.g. `"mg/100g"`. Required, free text. |
| `preparation_method` | Sample state the paper measured: `Raw`, `Boiled`, `Steamed`, `Dried`, … Free text. |
| `analytical_method` | Lab technique the **paper** used: `HPLC`, spectrophotometry, enzymatic assay, … Free text. |
| `sample_size` | Study sample size, if reported (`> 0`). |
| `confidence` | 0.0–1.0 score, if applicable. |
| `extraction_method` | How the data point entered **our** system: `manual \| automated \| pdf`. Required. |

**Two "method" fields, two different things.** `analytical_method` is a scientific
attribute of the measurement — the technique the *paper's authors* used in the lab.
`extraction_method` is *our pipeline's* provenance — how the number got into our
database: a human typed it (`manual`), a program pulled it from structured data
(`automated`), or it was lifted out of a PDF (`pdf`). They are orthogonal.

**Natural key** (unique index `compound_measurements_natural_key_index`):
`(study_id, ingredient_id, compound_id, preparation_method, analytical_method)`.
One measurement per compound-in-ingredient, per preparation, per analytical method,
per study. Re-extracting the same study **does not** duplicate rows.

**`on_delete` choices.** `ingredient_id`/`compound_id` cascade (`delete_all`) — a
measurement is meaningless without both. `study_id` **nilifies** rather than
deletes, so an immutable value survives its study row being pruned; `study_id` is
also optional, so a `manual` entry can be recorded before (or without) cataloging
the paper as a `ScientificStudy`.

**Postgres NULL caveat.** The natural key includes `study_id`, `preparation_method`,
and `analytical_method`. On PostgreSQL 14 (this deployment) NULLs are treated as
*distinct* in a unique index, so manual entries with a `nil` `study_id` (or nil
prep/method) are **not** deduped against each other. Idempotent re-extraction
relies on those key columns being present, which the automated/PDF paths supply.

**Indexes:** the natural-key unique index; `index (compound_id)`;
`index (study_id)`; `index (ingredient_id, compound_id)` (the aggregation read path).

---

## 3. Context API (`Mehungry.Food.CompoundMeasurements`, via the `Mehungry.Food` facade)

**Writes — insert only (measurements are immutable)**

```elixir
# Strict insert: a duplicate on the natural key surfaces as a changeset error.
Food.create_measurement(%{
  ingredient_id: spinach.id,
  compound_id: oxalate.id,
  study_id: study.id,
  value: 750.0,
  unit: "mg/100g",
  preparation_method: "Raw",
  analytical_method: "HPLC",
  sample_size: 12,
  confidence: 0.9,
  extraction_method: "manual"
})

# Idempotent insert: on the natural key a conflict does NOTHING — the original,
# immutable row is preserved and returned unchanged, never overwritten. Safe to
# call repeatedly from automated / PDF re-extraction.
Food.record_measurement(attrs)
```

**Reads — raw rows (aggregation is a separate layer)**

```elixir
Food.get_measurement!(id)
Food.list_measurements(ingredient_id, compound_id)  # every study's value, for aggregation
Food.list_measurements_for_ingredient(ingredient_id)
Food.list_measurements_for_compound(compound_id)
Food.list_measurements_for_study(study_id)
```

There is deliberately **no** `update_measurement` or upsert-replace. `create_*`
is the strict path; `record_*` is the idempotent path that keeps the first value.

---

## 4. Immutable — the hard boundary

This layer is **insert-and-read only**. The guarantees:

- **Historical values are never updated.** `record_measurement/1` inserts with
  `on_conflict: :nothing` on the natural key, so re-recording the same observation
  with a *different* value keeps the original — it never overwrites it.
- **New studies create new measurements.** A different `study_id` (or a different
  preparation / analytical method) is a distinct row, so conflicting values from
  different papers coexist rather than clobbering one another.
- **Aggregation happens separately.** Any mean, range, or per-preparation summary
  is computed by a *reader* over `list_measurements/2` and never mutates these
  rows. No aggregate is stored here.

The context exposes no update path; the changeset in `CompoundMeasurement` is
insert-only. Immutability is enforced structurally, not by convention.

---

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Food.CompoundMeasurements` | `food/compound_measurements.ex` | Context: insert-only writes, read/query API. |
| `Food.CompoundMeasurement` | `food/schemas/compound_measurement.ex` | Immutable measurement schema (insert-only changeset). |
| — | `priv/repo/migrations/20260730120000_create_compound_measurements.exs` | Table + natural-key unique index. |

All public functions are exposed via the `Mehungry.Food` facade (the
`create_measurement` / `record_measurement` / `list_measurements*` delegates).

---

## 6. Testing

`apps/mehungry/test/mehungry/food/compound_measurements_test.exs` covers the worked
example (Spinach / Oxalate / Raw / 750 mg/100g), all three `extraction_method`
values, manual entry with no linked study, immutability (idempotent re-record keeps
the original value; strict create rejects a duplicate; a new study / different
preparation yields a distinct row), the validations (required fields, non-negative
`value`, positive `sample_size`, `confidence` in 0.0–1.0, `extraction_method`
inclusion), and the read queries.

```bash
mix test apps/mehungry/test/mehungry/food/compound_measurements_test.exs
```

---

## 7. Out of scope / follow-ons

- **Aggregation layer.** Summarizing measurements per `(ingredient, compound)` —
  mean/median/range/variance and an evidence score — is a separate read-only
  concern that consumes these rows. It is built in `Mehungry.Food.EvidenceAggregation`
  (see **`docs/evidence_aggregation.md`**); per-preparation rollups and unit
  normalization remain follow-ons there.
- **Automated / PDF extraction pipeline.** The `automated` and `pdf`
  `extraction_method` values are supported by the schema, but an Oban worker that
  parses papers and calls `record_measurement/1` is a follow-on (it would mirror
  `LiteratureCrawlWorker` / `PubTatorAnnotationWorker`).
- **Unit normalization.** `unit` is stored verbatim as reported; converting
  `mg/100g` ↔ `µg/g` ↔ `g/kg` belongs in the aggregation reader, not this layer.
