defmodule Mehungry.Literature.ResearchType do
  @moduledoc """
  Maps the `mehungry_extractor` `study_design` string (persisted on
  `Mehungry.Literature.StudyAnalysis`) onto the evidence-hierarchy **buckets**
  the nutritionist research-search UI groups results into.

  The extractor emits a fine-grained design vocabulary (see
  `mehungry_extractor/knowledge/study.py`); nutritionists think in a coarser
  evidence pyramid. This module is the single, pure translation between the two
  — a bucket key, its human label, and a display `order` (ascending = shown
  first, strongest evidence on top). An unknown/`nil`/unmapped design falls to
  `:unknown` ("Unclassified"), never guessed.

  Facts only: no advice, no scoring — just a presentation grouping.
  """

  # Ordered buckets: {key, label, order}. Order is the display rank (1 = top).
  @buckets [
    {:systematic_review, "Systematic reviews & meta-analyses", 1},
    {:controlled_trial, "Randomized & controlled trials", 2},
    {:cohort, "Cohort studies", 3},
    {:case_control, "Case-control studies", 4},
    {:cross_sectional, "Cross-sectional & observational", 5},
    {:case_report, "Case reports & series", 6},
    {:guideline_review, "Guidelines & reviews", 7},
    {:preclinical_other, "Preclinical & other", 8},
    {:unknown, "Unclassified", 9}
  ]

  # Extractor `study_design` → bucket key. Exhaustive over the extractor's
  # `_PUBTYPE_DESIGN` / `_DESIGN_RANK` vocabulary.
  @design_bucket %{
    "systematic_review" => :systematic_review,
    "meta_analysis" => :systematic_review,
    "randomized_controlled_trial" => :controlled_trial,
    "controlled_trial" => :controlled_trial,
    "cohort" => :cohort,
    "case_control" => :case_control,
    "cross_sectional" => :cross_sectional,
    "case_report" => :case_report,
    "case_series" => :case_report,
    "guideline" => :guideline_review,
    "review" => :guideline_review,
    "editorial" => :preclinical_other,
    "letter" => :preclinical_other,
    "animal" => :preclinical_other,
    "in_vitro" => :preclinical_other
  }

  @labels Map.new(@buckets, fn {key, label, _order} -> {key, label} end)
  @orders Map.new(@buckets, fn {key, _label, order} -> {key, order} end)

  @type bucket_key ::
          :systematic_review
          | :controlled_trial
          | :cohort
          | :case_control
          | :cross_sectional
          | :case_report
          | :guideline_review
          | :preclinical_other
          | :unknown

  @doc "All buckets as `{key, label, order}`, in display order."
  @spec buckets() :: [{bucket_key(), String.t(), pos_integer()}]
  def buckets, do: @buckets

  @doc """
  The bucket key for an extractor `study_design`. A blank/`nil`/`"unknown"`/
  unmapped design resolves to `:unknown`.
  """
  @spec bucket(String.t() | nil) :: bucket_key()
  def bucket(design) when is_binary(design), do: Map.get(@design_bucket, design, :unknown)
  def bucket(_), do: :unknown

  @doc "Human label for a bucket key."
  @spec label(bucket_key()) :: String.t()
  def label(key), do: Map.get(@labels, key, "Unclassified")

  @doc "Display order for a bucket key (1 = top)."
  @spec order(bucket_key()) :: pos_integer()
  def order(key), do: Map.get(@orders, key, 99)
end
