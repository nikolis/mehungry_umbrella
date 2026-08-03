defmodule Mehungry.Health.RecommendationCandidates do
  @moduledoc """
  The two-stage candidate → curated pipeline for **condition↔compound
  recommendations** — the ADVISE-layer analogue of `Food.CompoundCandidates`.

  **Candidates** are *proposed* recommendations derived from the directional
  `study_entity_relations` PubTator extracted (a chemical↔disease relation whose
  endpoints resolved to a `Compound` and a `Condition`). Each pair's relations are
  tallied by valence, scored 0.0–1.0, and mapped to a *suggested* direction
  (negative-correlation → `encourage`, positive → `avoid`, association → `neutral`).

  Unlike the species pipeline, a recommendation candidate is **never auto-promoted** —
  PubMed relation extraction is weak grounds for medical dietary advice. An admin
  confirms the direction and severity, and **promotion** writes a
  `Health.CompoundRecommendation` (`source: "literature"`, conservative default
  `evidence_level`) and marks the candidate `promoted`. Re-derivation refreshes the
  evidence fields but never touches a decided status.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Literature
  alias Mehungry.Health

  alias Mehungry.Health.CompoundRecommendationCandidate, as: Candidate
  alias Mehungry.Health.CompoundRecommendationCandidateStudy, as: CandidateStudy

  # Relation-study count at which the strength component saturates to 1.0. Lower
  # than the co-occurrence saturation — extracted relations are rarer than mentions.
  @relation_saturation 3
  @association_types ~w(Association Cotreatment)

  # ── Scoring ────────────────────────────────────────────────────────────────

  @doc """
  Score a `(condition, compound)` pair from its extracted relations: a strength
  component from the number of backing studies blended (noisy-OR) with the best
  relation confidence, plus a valence tally that yields the suggested direction.
  """
  def score_candidate(condition_id, compound_id) do
    relations = Literature.condition_compound_relations(condition_id, compound_id)

    negative = Enum.count(relations, &(&1.type == "Negative_Correlation"))
    positive = Enum.count(relations, &(&1.type == "Positive_Correlation"))
    association = Enum.count(relations, &(&1.type in @association_types))

    study_count = relations |> Enum.map(& &1.study_id) |> Enum.uniq() |> length()
    max_score = relations |> Enum.map(&(&1.score || 0.0)) |> Enum.max(fn -> 0.0 end)

    strength = min(study_count / @relation_saturation, 1.0)
    score = Float.round(noisy_or(strength, max_score), 3)

    %{
      suggested_recommendation: suggest_direction(negative, positive),
      evidence_score: score,
      evidence_level: to_string(level(score)),
      study_count: study_count,
      relation_counts: %{
        "negative" => negative,
        "positive" => positive,
        "association" => association
      },
      sources: ["pubtator"],
      evidence: %{
        "strength_component" => Float.round(strength, 3),
        "confidence_component" => Float.round(max_score, 3),
        "relation_studies" => study_count,
        "negative" => negative,
        "positive" => positive,
        "association" => association
      }
    }
  end

  # Negative correlation → the compound is inversely associated with the condition →
  # lean encourage. Positive → lean avoid. Ties / association-only → neutral (review).
  defp suggest_direction(negative, positive) do
    cond do
      negative > positive -> "encourage"
      positive > negative -> "avoid"
      true -> "neutral"
    end
  end

  defp noisy_or(a, b), do: 1.0 - (1.0 - a) * (1.0 - b)

  defp level(score) do
    cond do
      score >= 0.75 -> :strong
      score >= 0.5 -> :moderate
      score >= 0.25 -> :limited
      true -> :insufficient
    end
  end

  # ── Derivation ─────────────────────────────────────────────────────────────

  @doc """
  Derive/refresh a candidate for the pair and refresh its reference-study links.
  **Never promotes.** Returns `{:ok, %{candidate: _, promoted: false}}` to match the
  batch/worker shape.
  """
  def derive_candidate(condition_id, compound_id) do
    attrs =
      score_candidate(condition_id, compound_id)
      |> Map.merge(%{condition_id: condition_id, compound_id: compound_id})

    {:ok, candidate} = upsert_candidate(attrs)

    replace_candidate_studies(
      candidate.id,
      Literature.condition_compound_relation_study_ids(condition_id, compound_id)
    )

    {:ok, %{candidate: candidate, promoted: false}}
  end

  @doc """
  Derive candidates for an `Enum.slice(offset, limit)` window of the relation pairs.
  Returns `{derived_count, 0}` — this stage never promotes.
  """
  def derive_candidates_batch(offset, limit) do
    Literature.condition_compound_relation_pairs()
    |> Enum.slice(offset, limit)
    |> Enum.reduce({0, 0}, fn {condition_id, compound_id}, {derived, promoted} ->
      {:ok, _} = derive_candidate(condition_id, compound_id)
      {derived + 1, promoted}
    end)
  end

  defp upsert_candidate(attrs) do
    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :suggested_recommendation,
           :evidence_score,
           :evidence_level,
           :relation_counts,
           :study_count,
           :sources,
           :evidence,
           :updated_at
         ]},
      conflict_target: [:condition_id, :compound_id],
      returning: true
    )
  end

  defp replace_candidate_studies(candidate_id, study_ids) do
    Repo.delete_all(from(cs in CandidateStudy, where: cs.candidate_id == ^candidate_id))

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(study_ids, fn study_id ->
        %{candidate_id: candidate_id, study_id: study_id, inserted_at: now, updated_at: now}
      end)

    if entries != [] do
      Repo.insert_all(CandidateStudy, entries, on_conflict: :nothing)
    end

    :ok
  end

  # ── Promotion / review (human-gated) ───────────────────────────────────────

  @doc """
  Promote a candidate into a curated `Health.CompoundRecommendation` and mark it
  `promoted`. The admin supplies the confirmed direction/severity in `attrs`
  (`:recommendation`, `:severity`, `:evidence_level`); the suggested direction is used
  only as a fallback. Always `source: "literature"`, `evidence_level` defaulting to a
  conservative `"limited"`. Accepts a struct or an id.
  """
  def promote_candidate(candidate, attrs \\ %{})

  def promote_candidate(%Candidate{} = candidate, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    recommendation = attrs["recommendation"] || fallback_direction(candidate)

    {:ok, recommendation_row} =
      Health.upsert_recommendation(%{
        condition_id: candidate.condition_id,
        compound_id: candidate.compound_id,
        recommendation: recommendation,
        severity: attrs["severity"],
        evidence_level: attrs["evidence_level"] || "limited",
        source: "literature",
        notes: promotion_note(candidate)
      })

    candidate
    |> Candidate.changeset(%{
      status: "promoted",
      promoted_recommendation_id: recommendation_row.id
    })
    |> Repo.update()
  end

  def promote_candidate(id, attrs), do: promote_candidate(get_candidate!(id), attrs)

  # "neutral"/nil suggestion has no valid CompoundRecommendation value — fall back to
  # the most conservative one so a promote without an explicit choice is still safe.
  defp fallback_direction(%Candidate{suggested_recommendation: s})
       when s in ~w(avoid limit caution encourage monitor),
       do: s

  defp fallback_direction(_candidate), do: "caution"

  defp promotion_note(%Candidate{} = c) do
    counts = c.relation_counts || %{}

    "Derived from #{c.study_count} relation stud#{plural(c.study_count)} " <>
      "(−#{counts["negative"] || 0} / +#{counts["positive"] || 0} / " <>
      "~#{counts["association"] || 0}; evidence: #{c.evidence_level || "insufficient"})"
  end

  defp plural(1), do: "y"
  defp plural(_), do: "ies"

  @doc "Mark a candidate `rejected` (leaves the review queue, writes no advice)."
  def reject_candidate(%Candidate{} = candidate),
    do: candidate |> Candidate.changeset(%{status: "rejected"}) |> Repo.update()

  def reject_candidate(id), do: reject_candidate(get_candidate!(id))

  # ── Queries ────────────────────────────────────────────────────────────────

  @doc "Pending candidates for review, strongest evidence first; `:limit`/`:offset` paged."
  def list_pending_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    Repo.all(
      from(c in Candidate,
        where: c.status == "pending",
        order_by: [desc: c.evidence_score, asc: c.id],
        preload: [:condition, :compound, :studies],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def list_candidates_for_condition(condition_id) do
    Repo.all(
      from(c in Candidate,
        where: c.condition_id == ^condition_id,
        order_by: [desc: c.evidence_score, asc: c.id],
        preload: [:compound, :studies]
      )
    )
  end

  def get_candidate!(id),
    do: Repo.get!(Candidate, id) |> Repo.preload([:condition, :compound, :studies])

  @doc "Coverage snapshot for the progress bar: pairs with a candidate row / all relation pairs."
  def recommendation_derivation_progress do
    total = Literature.count_condition_compound_relation_pairs()
    processed = Repo.aggregate(Candidate, :count, :id)
    %{processed: min(processed, total), total: total}
  end

  # ── Pipeline entry point ───────────────────────────────────────────────────

  @doc "Open a tracked derivation run and enqueue the first batch. Returns `{:ok, run}`."
  def enqueue_recommendation_derivation do
    run = Mehungry.Health.RecommendationDerivationRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.RecommendationCandidateDerivationWorker.new()
      |> Oban.insert()

    {:ok, run}
  end
end
