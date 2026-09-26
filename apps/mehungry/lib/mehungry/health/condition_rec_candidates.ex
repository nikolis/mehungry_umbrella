defmodule Mehungry.Health.ConditionRecCandidates do
  @moduledoc """
  The phase-aware recommendation-candidate pipeline — the state-aware sibling of
  `Health.RecommendationCandidates`.

  Unlike that engine (which derives candidates from state-blind PubTator relations
  in-process), candidates here are extracted from study **prose** by the offline
  Python service and posted back over the token-guarded REST API. This module owns:

    * the **pending** query the service pulls (`(study, condition)` pairs from the
      reverse crawl that haven't been extracted yet — `list_pending_extraction/1`),
    * the **termination ledger** (`record_extraction_attempt/1`),
    * the **upsert** of a posted finding into a review-gated candidate
      (`upsert_candidate/1` — resolves the raw term to a compound / nutrient / pattern
      and the state slug to a `ConditionState`, idempotent via `dedup_key`), and
    * the **review** queue + **promotion** into a `ConditionStateRecommendation`
      (`list_pending_candidates/1`, `promote_candidate/2`, `reject_candidate/1`).

  Nothing is ever auto-promoted.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.NutrientNameNormalizer

  alias Mehungry.Health

  alias Mehungry.Health.{
    ConditionState,
    ConditionRecommendationCandidate,
    ConditionRecommendationCandidateStudy,
    ConditionStateRecommendationStudy,
    ConditionRecExtractionAttempt
  }

  alias Mehungry.Literature.{ScientificStudy, StudyCondition}

  # ── Pending set served to the offline extractor ───────────────────────────

  @doc """
  `(study, condition)` pairs discovered by the reverse crawl that have **not** yet
  been extracted (no `condition_rec_extraction_attempts` row). Returns lightweight
  maps; the controller enriches each with the condition's states.
  """
  def list_pending_extraction(limit) do
    Repo.all(
      from(sc in StudyCondition,
        join: s in ScientificStudy,
        on: s.id == sc.study_id,
        left_join: a in ConditionRecExtractionAttempt,
        on: a.study_id == sc.study_id and a.condition_id == sc.condition_id,
        where: is_nil(a.id) and not is_nil(s.pmid),
        distinct: true,
        order_by: [desc: sc.study_id],
        limit: ^limit,
        select: %{study_id: sc.study_id, condition_id: sc.condition_id, pmid: s.pmid}
      )
    )
  end

  @doc "Extraction coverage: distinct extracted pairs / distinct crawled pairs."
  def extraction_progress do
    total =
      Repo.one(
        from(sc in StudyCondition, select: count(fragment("distinct (?, ?)", sc.study_id, sc.condition_id)))
      ) || 0

    processed = Repo.aggregate(ConditionRecExtractionAttempt, :count, :id)
    %{processed: processed, total: total}
  end

  @doc "Ledger a `(study, condition)` extraction attempt (upsert), so the pair leaves the pending set."
  def record_extraction_attempt(attrs) do
    %ConditionRecExtractionAttempt{}
    |> ConditionRecExtractionAttempt.changeset(normalize_keys(attrs))
    |> Repo.insert(
      on_conflict: {:replace, [:candidates_found, :updated_at]},
      conflict_target: [:study_id, :condition_id]
    )
  end

  # ── Candidate upsert (from a posted extraction finding) ────────────────────

  @doc """
  Upsert one extracted finding into a review-gated candidate. Resolves the raw term
  to a registry compound / canonical nutrient / free-text pattern and the state slug
  to a `ConditionState`, then upserts idempotently on the computed `dedup_key`
  (evidence fields refresh; a decided `status` is preserved). Additively links the
  posting study and refreshes `study_count`.
  """
  def upsert_candidate(attrs) do
    a = normalize_keys(attrs)

    condition_id = a[:condition_id]
    raw_term = a[:raw_term]
    target_kind = a[:target_kind] || "food_pattern"
    state_id = resolve_state(condition_id, a[:condition_state_slug])
    {compound_id, nutrient_name} = resolve_target(target_kind, raw_term)

    row = %{
      condition_id: condition_id,
      condition_state_id: state_id,
      compound_id: compound_id,
      nutrient_name: nutrient_name,
      raw_term: raw_term,
      target_kind: target_kind,
      suggested_recommendation: a[:suggested_recommendation] || a[:direction],
      suggested_severity: a[:suggested_severity] || a[:severity],
      evidence_score: a[:evidence_score] || a[:confidence] || 0.0,
      confidence: a[:confidence],
      evidence_level: a[:evidence_level],
      evidence: build_evidence(a),
      extraction_method: a[:extraction_method] || "llm_fulltext",
      dedup_key: dedup_key(condition_id, state_id, compound_id, nutrient_name, raw_term)
    }

    %ConditionRecommendationCandidate{}
    |> ConditionRecommendationCandidate.changeset(row)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [
           :condition_state_id,
           :compound_id,
           :nutrient_name,
           :target_kind,
           :suggested_recommendation,
           :suggested_severity,
           :evidence_score,
           :confidence,
           :evidence_level,
           :evidence,
           :extraction_method,
           :updated_at
         ]},
      conflict_target: [:dedup_key],
      returning: true
    )
    |> case do
      {:ok, candidate} ->
        link_candidate_study(candidate.id, a[:study_id])
        {:ok, Repo.get!(ConditionRecommendationCandidate, candidate.id)}

      other ->
        other
    end
  end

  # ── Review queue ──────────────────────────────────────────────────────────

  @doc "Pending candidates, richest evidence first, with associations preloaded (admin review)."
  def list_pending_candidates(limit \\ 200) do
    Repo.all(
      from(c in ConditionRecommendationCandidate,
        where: c.status == "pending",
        order_by: [asc: c.condition_id, desc: c.evidence_score, desc: c.id],
        limit: ^limit,
        preload: [:condition, :condition_state, :compound, :studies]
      )
    )
  end

  def list_candidates_for_condition(condition_id) do
    Repo.all(
      from(c in ConditionRecommendationCandidate,
        where: c.condition_id == ^condition_id,
        order_by: [desc: c.evidence_score, desc: c.id],
        preload: [:condition_state, :compound, :studies]
      )
    )
  end

  def get_candidate!(id) do
    Repo.get!(ConditionRecommendationCandidate, id)
    |> Repo.preload([:condition, :condition_state, :compound, :studies])
  end

  @doc "Reject a candidate — kept for audit, excluded from the queue, never re-derived away."
  def reject_candidate(%ConditionRecommendationCandidate{} = candidate) do
    candidate
    |> ConditionRecommendationCandidate.changeset(%{status: "rejected"})
    |> Repo.update()
  end

  def reject_candidate(id), do: id |> get_candidate!() |> reject_candidate()

  # ── Promotion → the decoupled ConditionStateRecommendation store ───────────

  @doc """
  Promote a reviewed candidate into a `ConditionStateRecommendation` (`source:
  "literature"`). The admin confirms the direction (`recommendation`), `severity`, and
  optionally overrides `condition_state_id` (defaults to the candidate's). The
  candidate's studies are **frozen** into `condition_state_recommendation_studies`, the
  candidate is marked `promoted` and back-linked. Idempotent on the store's dedup key.

  `attrs` keys: `"recommendation"` (required — the suggestion is a hint), `"severity"`,
  `"condition_state_id"`, `"evidence_level"`.
  """
  def promote_candidate(candidate_id, attrs) when is_integer(candidate_id) do
    promote_candidate(get_candidate!(candidate_id), attrs)
  end

  def promote_candidate(%ConditionRecommendationCandidate{} = candidate, attrs) do
    a = normalize_keys(attrs)
    state_id = a[:condition_state_id] || candidate.condition_state_id

    rec_attrs = %{
      condition_id: candidate.condition_id,
      condition_state_id: state_id,
      compound_id: candidate.compound_id,
      nutrient_name: candidate.nutrient_name,
      raw_food_term: if(is_nil(candidate.compound_id) and is_nil(candidate.nutrient_name), do: candidate.raw_term),
      recommendation: a[:recommendation] || fallback_direction(candidate),
      severity: a[:severity] || candidate.suggested_severity,
      evidence_level: a[:evidence_level] || candidate.evidence_level || "limited",
      source: "literature",
      notes: promotion_note(candidate)
    }

    with {:ok, rec} <- Health.upsert_state_recommendation(rec_attrs) do
      freeze_recommendation_studies(candidate, rec)

      candidate
      |> ConditionRecommendationCandidate.changeset(%{
        status: "promoted",
        promoted_recommendation_id: rec.id
      })
      |> Repo.update()

      {:ok, rec}
    end
  end

  # The suggestion is only a hint; fall back to a safe "caution" if it's not a valid
  # recommendation value (e.g. "neutral").
  defp fallback_direction(%{suggested_recommendation: s})
       when s in ~w(avoid limit caution encourage monitor),
       do: s

  defp fallback_direction(_), do: "caution"

  defp promotion_note(%{raw_term: raw_term, evidence: evidence}) do
    snippet = if is_map(evidence), do: evidence["snippet"], else: nil
    ["extracted: #{raw_term}", snippet] |> Enum.reject(&is_nil/1) |> Enum.join(" — ")
  end

  # Copy the candidate's backing studies into the frozen provenance table (idempotent);
  # re-extraction never touches these, so the recommendation keeps its validated citations.
  defp freeze_recommendation_studies(candidate, rec) do
    study_ids =
      Repo.all(
        from(cs in ConditionRecommendationCandidateStudy,
          where: cs.candidate_id == ^candidate.id,
          select: cs.study_id
        )
      )

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(study_ids, fn sid ->
        %{recommendation_id: rec.id, study_id: sid, inserted_at: now, updated_at: now}
      end)

    Repo.insert_all(ConditionStateRecommendationStudy, rows, on_conflict: :nothing)
  end

  # ── internals ─────────────────────────────────────────────────────────────

  # Resolve the extractor's state slug to a ConditionState id (nil = general/all-phase).
  defp resolve_state(_condition_id, slug) when slug in [nil, "", "general"], do: nil

  defp resolve_state(condition_id, slug) do
    Repo.one(
      from(s in ConditionState,
        where: s.condition_id == ^condition_id and s.slug == ^slug,
        select: s.id
      )
    )
  end

  # Ground the raw term. Never mutates the registry from unreviewed extraction — an
  # unknown compound stays unresolved (raw_term only) for the admin.
  defp resolve_target("compound", raw_term) do
    case Food.get_compound_by_name(raw_term) do
      %{id: id} -> {id, nil}
      _ -> {nil, nil}
    end
  end

  defp resolve_target("nutrient", raw_term), do: {nil, NutrientNameNormalizer.normalize(raw_term)}
  defp resolve_target(_food_pattern, _raw_term), do: {nil, nil}

  defp dedup_key(condition_id, state_id, compound_id, nutrient_name, raw_term) do
    target =
      cond do
        compound_id -> "c#{compound_id}"
        is_binary(nutrient_name) and nutrient_name != "" -> "n#{norm(nutrient_name)}"
        true -> "r#{norm(raw_term)}"
      end

    "#{condition_id}|#{state_id || 0}|#{target}"
  end

  defp norm(nil), do: ""
  defp norm(s), do: s |> to_string() |> String.trim() |> String.downcase()

  defp build_evidence(a) do
    %{}
    |> put_if("snippet", a[:evidence_snippet] || a[:snippet])
    |> put_if("rationale", a[:rationale])
    |> Map.merge(if(is_map(a[:evidence]), do: a[:evidence], else: %{}))
  end

  defp put_if(map, _k, nil), do: map
  defp put_if(map, k, v), do: Map.put(map, k, v)

  defp link_candidate_study(_candidate_id, nil), do: :ok

  defp link_candidate_study(candidate_id, study_id) do
    %ConditionRecommendationCandidateStudy{}
    |> ConditionRecommendationCandidateStudy.changeset(%{
      candidate_id: candidate_id,
      study_id: study_id
    })
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:candidate_id, :study_id])

    count =
      Repo.aggregate(
        from(cs in ConditionRecommendationCandidateStudy, where: cs.candidate_id == ^candidate_id),
        :count
      )

    Repo.update_all(
      from(c in ConditionRecommendationCandidate, where: c.id == ^candidate_id),
      set: [study_count: count]
    )

    :ok
  end

  # Accept JSON (string-keyed) or atom-keyed maps uniformly; drop keys we don't
  # recognise (an unexpected JSON field must never crash `to_existing_atom`).
  defp normalize_keys(attrs) do
    Enum.reduce(attrs, %{}, fn {k, v}, acc ->
      case to_atom(k) do
        nil -> acc
        atom -> Map.put(acc, atom, v)
      end
    end)
  end

  defp to_atom(k) when is_atom(k), do: k

  defp to_atom(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> nil
  end
end
