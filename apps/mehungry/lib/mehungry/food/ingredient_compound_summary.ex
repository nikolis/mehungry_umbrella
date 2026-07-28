defmodule Mehungry.Food.IngredientCompoundSummary do
  @moduledoc """
  A computed, read-only summary of every `CompoundMeasurement` recorded for one
  `(ingredient, compound)` pair — the aggregated evidence for e.g.
  *Spinach / Oxalate*.

  This is **not** an Ecto schema and is never persisted. It is produced on demand
  by `Mehungry.Food.EvidenceAggregation` from the immutable measurement rows and
  never mutates them (see `docs/compound_measurements.md` §4).

  ## Fields

  Descriptive statistics are computed over the measurements sharing the summary's
  `unit` (the modal unit — see `EvidenceAggregation` for why units are not mixed):

    * `mean`, `median`, `min`, `max` — the central value and range.
    * `variance`, `std_dev` — spread, as *population* statistics of the observed
      values (denominator `n`), a description of the data we hold rather than an
      inferential estimate of a population parameter.
    * `study_count` — distinct cataloged studies contributing (nil `study_id`
      manual entries are not counted as studies).
    * `measurement_count` — observations in the summarized `unit`.
    * `total_measurement_count` / `units_present` — how many observations exist in
      *all* units, so a caller can see when heterogeneous units were present and
      only the modal subset was summarized.

  The evidence assessment is deliberately auditable, not a black box:

    * `evidence_score` — 0.0–1.0, a weighted blend of the components below.
    * `evidence_components` — the five 0.0–1.0 factor scores that produced it
      (`:study_count`, `:consistency`, `:analytical_method`, `:recency`,
      `:publication_quality`).
    * `evidence_level` — a categorical label of that score:
      `:strong | :moderate | :limited | :insufficient`.

  ## Not medical advice

  `evidence_level` describes **how well-supported the measured numbers are** — the
  strength of the *measurement evidence*, nothing more. It is not a dietary
  recommendation, a safety threshold, or a health claim. Any user-facing guidance
  belongs in a separate layer that reads these summaries; this struct only
  summarizes evidence.
  """

  @type evidence_level :: :strong | :moderate | :limited | :insufficient

  @type t :: %__MODULE__{
          ingredient_id: integer() | nil,
          compound_id: integer() | nil,
          unit: String.t() | nil,
          mean: float() | nil,
          median: float() | nil,
          min: float() | nil,
          max: float() | nil,
          variance: float() | nil,
          std_dev: float() | nil,
          study_count: non_neg_integer(),
          measurement_count: non_neg_integer(),
          total_measurement_count: non_neg_integer(),
          units_present: [String.t()],
          evidence_score: float(),
          evidence_components: %{atom() => float()},
          evidence_level: evidence_level()
        }

  defstruct ingredient_id: nil,
            compound_id: nil,
            unit: nil,
            mean: nil,
            median: nil,
            min: nil,
            max: nil,
            variance: nil,
            std_dev: nil,
            study_count: 0,
            measurement_count: 0,
            total_measurement_count: 0,
            units_present: [],
            evidence_score: 0.0,
            evidence_components: %{},
            evidence_level: :insufficient
end
