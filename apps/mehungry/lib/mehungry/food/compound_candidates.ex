defmodule Mehungry.Food.CompoundCandidates do
  @moduledoc """
  The two-stage candidate → curated pipeline for ingredient↔compound relationships.

  **Candidates** are *proposed* relationships derived from existing evidence —
  PubTator co-occurrence (a resolved chemical mentioned in a paper linked to the
  ingredient), compound measurements, or manual import — scored 0.0–1.0 and staged
  `pending → promoted | rejected`. **Promotion** writes the curated fact into
  `IngredientCompoundRelationship` (via `Food.Compounds`), either automatically when
  the score clears `candidate_promotion_threshold` or by admin review.

  This is the "separate human-curation step" the fact layers defer to: PubTator /
  literature never write relationships directly (`docs/pubtator.md` §1,
  `docs/food_compounds.md` §4). The candidate table stays separate from the facts
  table so unreviewed proposals never masquerade as facts. Mirrors the
  `IngredientTaxonomyNode` candidate/review pattern.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Literature

  alias Mehungry.Food.Compounds
  alias Mehungry.Food.CompoundMeasurement
  alias Mehungry.Food.EvidenceAggregation
  alias Mehungry.Food.IngredientCompoundCandidate, as: Candidate

  # Co-occurrence studies at which the literature component saturates to 1.0.
  @cooccurrence_saturation 5
  # Default auto-promotion cutoff; overridable via config (see `promotion_threshold/0`).
  @default_promotion_threshold 0.75

  # ── Evidence enumeration ──────────────────────────────────────────────────

  @doc """
  Deterministic, deduped union of `{ingredient_id, compound_id}` pairs that carry
  any derivable evidence (literature co-occurrence ∪ compound measurements). The
  stable sort makes offset-paged batch derivation reproducible.
  """
  def evidence_pairs do
    lit =
      Literature.compound_ingredient_cooccurrences()
      |> Enum.map(&{&1.ingredient_id, &1.compound_id})

    (lit ++ measurement_pairs())
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "How many evidence pairs exist — the derivation run's `total`."
  def count_evidence_pairs, do: length(evidence_pairs())

  defp measurement_pairs do
    Repo.all(
      from(m in CompoundMeasurement, distinct: true, select: {m.ingredient_id, m.compound_id})
    )
  end

  # ── Scoring ───────────────────────────────────────────────────────────────

  @doc """
  Score the `(ingredient_id, compound_id)` pair, blending literature co-occurrence
  and measurement evidence with **noisy-OR** (`1 − (1−lit)·(1−meas)`) so strong
  evidence from *either* source can reach "strong", and both compound. Returns the
  attrs map used to upsert a candidate (score, level, counts, sources, audit).
  """
  def score_candidate(ingredient_id, compound_id) do
    study_count = Literature.cooccurrence_study_count(ingredient_id, compound_id)
    literature = min(study_count / @cooccurrence_saturation, 1.0)

    {measurement, measurement_study_count, has_measurements} =
      case EvidenceAggregation.summarize(ingredient_id, compound_id) do
        {:ok, summary} -> {summary.evidence_score, summary.study_count, true}
        {:error, :no_measurements} -> {0.0, 0, false}
      end

    score = Float.round(noisy_or(literature, measurement), 3)

    sources =
      []
      |> maybe_add(study_count > 0, "pubtator")
      |> maybe_add(has_measurements, "measurement")

    %{
      evidence_score: score,
      evidence_level: to_string(level(score)),
      study_count: study_count,
      measurement_study_count: measurement_study_count,
      sources: sources,
      evidence: %{
        "literature_component" => Float.round(literature, 3),
        "measurement_component" => Float.round(measurement, 3),
        "cooccurrence_studies" => study_count,
        "measurement_studies" => measurement_study_count
      }
    }
  end

  defp noisy_or(a, b), do: 1.0 - (1.0 - a) * (1.0 - b)

  # Same cutoffs as `Food.EvidenceAggregation` so levels read consistently.
  defp level(score) do
    cond do
      score >= 0.75 -> :strong
      score >= 0.5 -> :moderate
      score >= 0.25 -> :limited
      true -> :insufficient
    end
  end

  defp maybe_add(list, true, item), do: list ++ [item]
  defp maybe_add(list, false, _item), do: list

  # ── Derivation ────────────────────────────────────────────────────────────

  @doc """
  Derive/refresh a candidate for the pair from current evidence, then auto-promote
  it when it is still `pending` and scores at/above the promotion threshold.
  Re-derivation refreshes the evidence fields but never touches a `promoted`/
  `rejected` candidate's status. Returns `{:ok, %{candidate: _, promoted: boolean}}`.
  """
  def derive_candidate(ingredient_id, compound_id, opts \\ []) do
    attrs =
      score_candidate(ingredient_id, compound_id)
      |> Map.merge(%{
        ingredient_id: ingredient_id,
        compound_id: compound_id,
        relationship_type: "contains"
      })

    {:ok, candidate} = upsert_candidate(attrs)
    maybe_auto_promote(candidate, opts)
  end

  @doc """
  Derive candidates for a `Enum.slice(offset, limit)` window of `evidence_pairs/0`.
  Returns `{derived_count, promoted_count}`.
  """
  def derive_candidates_batch(offset, limit, opts \\ []) do
    evidence_pairs()
    |> Enum.slice(offset, limit)
    |> Enum.reduce({0, 0}, fn {ingredient_id, compound_id}, {derived, promoted} ->
      case derive_candidate(ingredient_id, compound_id, opts) do
        {:ok, %{promoted: true}} -> {derived + 1, promoted + 1}
        {:ok, _} -> {derived + 1, promoted}
      end
    end)
  end

  # Upsert on the natural key, replacing only the evidence fields — status,
  # sources-of-truth for review, and notes are preserved across re-derivation.
  defp upsert_candidate(attrs) do
    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :evidence_score,
           :evidence_level,
           :study_count,
           :measurement_study_count,
           :sources,
           :evidence,
           :updated_at
         ]},
      conflict_target: [:ingredient_id, :compound_id, :relationship_type],
      returning: true
    )
  end

  defp maybe_auto_promote(%Candidate{status: "pending", evidence_score: score} = candidate, opts) do
    threshold = Keyword.get(opts, :threshold, promotion_threshold())

    if is_number(score) and score >= threshold do
      {:ok, promoted} = do_promote(candidate, "literature")
      {:ok, %{candidate: promoted, promoted: true}}
    else
      {:ok, %{candidate: candidate, promoted: false}}
    end
  end

  defp maybe_auto_promote(candidate, _opts), do: {:ok, %{candidate: candidate, promoted: false}}

  # ── Promotion / review ────────────────────────────────────────────────────

  @doc """
  Promote a candidate into a curated `IngredientCompoundRelationship` fact and mark
  it `promoted`. Idempotent — the fact upsert and the status flip both no-op on
  re-promote. Accepts a struct or an id.
  """
  def promote_candidate(%Candidate{} = candidate),
    do: do_promote(candidate, promotion_source(candidate))

  def promote_candidate(id), do: promote_candidate(get_candidate!(id))

  defp do_promote(%Candidate{} = candidate, source) do
    {:ok, relationship} =
      Compounds.upsert_compound_relationship(%{
        ingredient_id: candidate.ingredient_id,
        compound_id: candidate.compound_id,
        relationship_type: candidate.relationship_type,
        source: source,
        confidence: candidate.evidence_score,
        notes: promotion_note(candidate)
      })

    candidate
    |> Candidate.changeset(%{status: "promoted", promoted_relationship_id: relationship.id})
    |> Repo.update()
  end

  # Manual-origin candidates promote as a manual fact; derived ones as literature.
  defp promotion_source(%Candidate{sources: sources}) do
    if is_list(sources) and "manual" in sources, do: "manual", else: "literature"
  end

  defp promotion_note(%Candidate{} = c) do
    "Promoted from #{c.study_count} co-occurrence stud#{plural(c.study_count)}, " <>
      "#{c.measurement_study_count} measurement stud#{plural(c.measurement_study_count)} " <>
      "(evidence: #{c.evidence_level || "insufficient"})"
  end

  defp plural(1), do: "y"
  defp plural(_), do: "ies"

  @doc "Mark a candidate `rejected` (leaves the review queue, writes no fact)."
  def reject_candidate(%Candidate{} = candidate),
    do: candidate |> Candidate.changeset(%{status: "rejected"}) |> Repo.update()

  def reject_candidate(id), do: reject_candidate(get_candidate!(id))

  @doc """
  Insert a human-asserted candidate (source `manual`) for a pair. `attrs` may carry
  `:relationship_type`, `:evidence_score`, `:notes`. Idempotent on the natural key.
  """
  def import_manual_candidate(ingredient_id, compound_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{ingredient_id: ingredient_id, compound_id: compound_id, sources: ["manual"]})
      |> Map.put_new(:relationship_type, "contains")
      |> Map.put_new(:status, "pending")

    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:notes, :updated_at]},
      conflict_target: [:ingredient_id, :compound_id, :relationship_type],
      returning: true
    )
  end

  # ── Config ────────────────────────────────────────────────────────────────

  @doc "Auto-promotion cutoff (0.0–1.0); `config :mehungry, :candidate_promotion_threshold`."
  def promotion_threshold do
    Application.get_env(:mehungry, :candidate_promotion_threshold, @default_promotion_threshold)
  end

  # ── Queries ───────────────────────────────────────────────────────────────

  @doc "Pending candidates for review, strongest evidence first; `:limit`/`:offset` paged."
  def list_pending_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(c in Candidate,
        where: c.status == "pending",
        order_by: [desc: c.evidence_score, asc: c.id],
        preload: [:ingredient, :compound],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def list_candidates_for_ingredient(ingredient_id) do
    Repo.all(
      from(c in Candidate,
        where: c.ingredient_id == ^ingredient_id,
        order_by: [desc: c.evidence_score, asc: c.id],
        preload: [:compound]
      )
    )
  end

  def get_candidate!(id), do: Repo.get!(Candidate, id) |> Repo.preload([:ingredient, :compound])

  @doc "Coverage snapshot for the progress bar: pairs with a candidate row / all evidence pairs."
  def candidate_derivation_progress do
    total = count_evidence_pairs()
    processed = Repo.aggregate(Candidate, :count, :id)
    %{processed: min(processed, total), total: total}
  end

  # ── Pipeline entry point ──────────────────────────────────────────────────

  @doc "Open a tracked derivation run and enqueue the first batch. Returns `{:ok, run}`."
  def enqueue_candidate_derivation do
    run = Mehungry.Food.CandidateDerivationRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.CompoundCandidateDerivationWorker.new()
      |> Oban.insert()

    {:ok, run}
  end
end
