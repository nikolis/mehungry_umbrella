# Evidence Aggregation

A **read-only aggregation layer** over the immutable compound-measurement rows. It
reads every observation for an `(ingredient, compound)` pair and computes an
`IngredientCompoundSummary` — descriptive statistics plus a transparent evidence
score. It stores nothing and mutates nothing.

> Example: *Spinach / Oxalate* → mean **750 mg/100g**, range **600–900**, **14**
> studies, evidence **Strong**.

```
   compound_measurements ── aggregate ──▶ IngredientCompoundSummary        ← this doc
   (immutable per-study        (read-only)   (mean/median/range/variance +
    observations,                            evidence score, computed on demand)
    docs/science/compound_measurements.md)
```

Where `docs/science/compound_measurements.md` records the individual numbers a paper
reported, this layer answers *"taking every study together, what's the central
value, how much do they agree, and how strong is the evidence?"*.

---

## 1. Why this exists

`compound_measurements.md` §7 explicitly defers the aggregation layer:
summarizing measurements per `(ingredient, compound)` — mean/range, spread,
evidence strength — is a separate read-only concern that consumes the raw rows and
never mutates them. This is that layer.

**Boundaries honored:**

- **Computed, never persisted.** `IngredientCompoundSummary` is a plain struct, not
  an Ecto schema. No aggregate is stored (honors `compound_measurements.md` §4); it
  is recomputed on demand from the immutable rows.
- **No fabricated unit conversions.** Units are free text; heterogeneous units are
  never silently averaged (see §3).
- **Facts only — no advice.** `evidence_level` measures how well-supported the
  *numbers* are, not whether a food is good or bad to eat. This layer summarizes
  evidence and produces no dietary recommendation, threshold, or health claim.

---

## 2. API (`Mehungry.Food.EvidenceAggregation`, via the `Mehungry.Food` facade)

```elixir
Food.summarize(ingredient_id, compound_id)
#=> {:ok, %IngredientCompoundSummary{mean: 750.0, min: 600.0, max: 900.0,
#         study_count: 14, evidence_level: :strong, ...}}
#=> {:error, :no_measurements}          # the pair has no recorded observations

Food.summarize_for_ingredient(ingredient_id)
#=> [%IngredientCompoundSummary{}, ...]  # one per compound, ascending compound_id
```

Both read `compound_measurements` (preloading the linked `ScientificStudy` for
recency/quality signals) and never write.

---

## 3. Statistics

Computed over the values sharing the summary's `unit`:

| Field | Meaning |
|---|---|
| `mean`, `median` | Central value (`median` averages the two middle values on an even count). |
| `min`, `max` | Actual reported extremes (the "600–900" range). |
| `variance`, `std_dev` | Spread as **population** statistics `Σ(x−mean)²/n` — a description of the data we hold, not an inferential estimate. `<2` values → `0.0`. |
| `study_count` | Distinct cataloged studies (nil-`study_id` manual entries are not counted as studies). |
| `measurement_count` | Observations in the summarized `unit`. |
| `total_measurement_count`, `units_present` | Observations across **all** units, so unit heterogeneity is visible. |

**Units are not mixed.** `unit` is free text, and averaging `mg/100g` with `g/kg`
without conversion would be nonsense. The summary aggregates over the **modal
unit** (most frequently reported; ties broken alphabetically) and surfaces
`units_present` / `total_measurement_count` so a caller sees when other units were
present and excluded. Unit normalization (`mg/100g ↔ µg/g ↔ g/kg`) is a deliberate
follow-on, not done here.

---

## 4. Evidence score

`evidence_score` (0.0–1.0) is a documented, auditable weighted blend of five
components, each also returned on `evidence_components` so the rating is never a
black box:

| Component | Weight | Basis |
|---|---|---|
| `:study_count` | 0.30 | `min(distinct_studies / 10, 1.0)` — saturates at 10 studies. |
| `:consistency` | 0.25 | Coefficient of variation `cv = std/mean`: `clamp(1 − cv/0.5, 0, 1)`. `<2` values or `mean == 0` → neutral `0.5`. |
| `:analytical_method` | 0.20 | Average lab-technique tier: HPLC/LC-MS/GC-MS/chromatography `1.0`; spectrophotometry/enzymatic/colorimetric/titration/ELISA `0.6`; estimated/calculated/NIR `0.3`; unknown/nil `0.4`. |
| `:recency` | 0.15 | Newest linked study's year: age ≤ 2 → `1.0`, linear down to `0.1` by age 15; no parseable date → neutral `0.4`. |
| `:publication_quality` | 0.10 | `0.5·(fraction backed by a cataloged study) + 0.5·(sample-size signal = min(avg sample_size/30, 1.0), or 0.3 if none reported)`. |

`evidence_score = Σ weightᵢ · componentᵢ`.

`evidence_level` labels the score: `:strong ≥ 0.75`, `:moderate ≥ 0.5`,
`:limited ≥ 0.25`, else `:insufficient`.

**Guardrail.** A pair backed by **≤ 1 study** is capped at `:limited` regardless of
score — a single paper can never read as "Strong" — but is not floored, so a lone
weak measurement can still be `:insufficient`.

The component weights and analytical-method tiers live in module attributes
(`@component_weights`, `@analytical_tier_scores`) and are tunable in one place.

---

## 5. Module map

| Module | File | Role |
|---|---|---|
| `Food.EvidenceAggregation` | `food/evidence_aggregation.ex` | The service: query + statistics + scoring. |
| `Food.IngredientCompoundSummary` | `food/ingredient_compound_summary.ex` | The computed result struct (not persisted). |

Both public functions are exposed via the `Mehungry.Food` facade
(`summarize/2`, `summarize_for_ingredient/1`).

---

## 6. Testing

`apps/mehungry/test/mehungry/food/evidence_aggregation_test.exs` covers the
Spinach/Oxalate worked example (mean/median/min/max/variance/study_count and
`:strong`), the population-variance math, `{:error, :no_measurements}`, the
single-study `:limited` cap, modal-unit selection with `units_present`, the
analytical/recency/publication-quality components moving with their inputs, and
`summarize_for_ingredient/1`.

```bash
mix test apps/mehungry/test/mehungry/food/evidence_aggregation_test.exs
```

---

## 7. Out of scope / follow-ons

- **Per-preparation rollups.** The summary aggregates across preparation methods
  (Raw, Boiled, …); breaking out a summary per preparation is a natural extension
  over the same reader.
- **Unit normalization.** Cross-unit conversion so all observations feed one
  summary (rather than modal-unit-only) belongs here as a follow-on.
- **Caching.** Summaries are recomputed on each call; if the read path gets hot, a
  Cachex layer keyed by `(ingredient_id, compound_id)` (invalidated on new
  measurements) would slot in without changing the API.
