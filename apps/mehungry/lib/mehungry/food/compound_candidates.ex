defmodule Mehungry.Food.CompoundCandidates do
  @moduledoc """
  The two-stage candidate → curated pipeline for **species**↔compound relationships.

  **Candidates** are *proposed* relationships derived from existing evidence —
  PubTator co-occurrence aggregated to the `FoundementalFoodSpecies` level (a resolved
  chemical mentioned in a paper linked to any ingredient of the species), species
  measurements, or manual import — scored 0.0–1.0 and staged `pending → promoted |
  rejected`. Each candidate links to the **reference studies** the co-occurrence was
  extracted from (`SpeciesCompoundCandidateStudy`). **Promotion** writes the curated
  fact into `SpeciesCompoundRelationship` (via `Food.SpeciesCompounds`), automatically
  when the score clears `candidate_promotion_threshold` or by admin review.

  Working at the species level yields one suggestion/fact per species rather than one
  per USDA ingredient variant. The candidate table stays separate from the facts table
  so unreviewed proposals never masquerade as facts.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Mehungry.Repo
  alias Mehungry.Literature

  alias Mehungry.Food.Compound
  alias Mehungry.Food.CompoundMeasurement
  alias Mehungry.Food.CompoundPlausibility
  alias Mehungry.Food.EvidenceAggregation
  alias Mehungry.Food.FoundementalFood
  alias Mehungry.Food.FoundementalFoodSpecies
  alias Mehungry.Food.SpeciesCompounds
  alias Mehungry.Food.SpeciesCompoundCandidate, as: Candidate
  alias Mehungry.Food.SpeciesCompoundCandidateStudy
  alias Mehungry.Food.SpeciesCompoundRelationship
  alias Mehungry.Food.SpeciesCompoundRelationshipStudy

  # Co-occurrence studies at which the literature component saturates to 1.0.
  @cooccurrence_saturation 5
  # Default auto-promotion cutoff; overridable via config (see `promotion_threshold/0`).
  @default_promotion_threshold 0.75

  # ── Evidence enumeration ──────────────────────────────────────────────────

  @doc """
  Deterministic, deduped union of `{species_id, compound_id}` pairs that carry any
  derivable evidence (literature co-occurrence ∪ compound measurements), minus the
  non-dietary blocklist. The stable sort makes offset-paged batch derivation
  reproducible.
  """
  def evidence_pairs do
    blocked = MapSet.new(blocklisted_compound_ids())

    lit =
      Literature.species_compound_cooccurrences()
      |> Enum.map(&{&1.species_id, &1.compound_id})

    (lit ++ measurement_pairs())
    |> Enum.uniq()
    |> Enum.reject(fn {_species_id, compound_id} -> MapSet.member?(blocked, compound_id) end)
    |> Enum.sort()
  end

  @doc "How many evidence pairs exist — the derivation run's `total`."
  def count_evidence_pairs, do: length(evidence_pairs())

  # Distinct `(species_id, compound_id)` pairs that have a measurement, mapping each
  # measured ingredient up to its species.
  defp measurement_pairs do
    Repo.all(
      from(m in CompoundMeasurement,
        join: ff in FoundementalFood,
        on: ff.ingredient_id == m.ingredient_id,
        distinct: true,
        select: {ff.foundemental_species_id, m.compound_id}
      )
    )
  end

  # ── Scoring ───────────────────────────────────────────────────────────────

  @doc """
  Score the `(species_id, compound_id)` pair, blending literature co-occurrence and
  measurement evidence with **noisy-OR** (`1 − (1−lit)·(1−meas)`) so strong evidence
  from *either* source can reach "strong", and both compound. Returns the attrs map
  used to upsert a candidate (score, level, counts, sources, audit).
  """
  def score_candidate(species_id, compound_id) do
    study_count = Literature.species_cooccurrence_study_count(species_id, compound_id)
    literature = min(study_count / @cooccurrence_saturation, 1.0)

    {measurement, measurement_study_count, has_measurements} =
      case EvidenceAggregation.summarize_species(species_id, compound_id) do
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
  Derive/refresh a candidate for the pair from current evidence, refresh its
  reference-study links, then auto-promote it when it is still `pending` and scores
  at/above the promotion threshold. Re-derivation refreshes evidence fields but never
  touches a `promoted`/`rejected` candidate's status. Returns
  `{:ok, %{candidate: _, promoted: boolean}}`.
  """
  def derive_candidate(species_id, compound_id, opts \\ []) do
    attrs =
      score_candidate(species_id, compound_id)
      |> Map.merge(%{
        foundemental_species_id: species_id,
        compound_id: compound_id,
        relationship_type: "contains"
      })

    {:ok, candidate} = upsert_candidate(attrs)

    replace_candidate_studies(
      candidate.id,
      Literature.species_cooccurrence_studies(species_id, compound_id)
    )

    maybe_auto_promote(candidate, opts)
  end

  @doc """
  Derive candidates for a `Enum.slice(offset, limit)` window of `evidence_pairs/0`.
  Returns `{derived_count, promoted_count}`.
  """
  def derive_candidates_batch(offset, limit, opts \\ []) do
    evidence_pairs()
    |> Enum.slice(offset, limit)
    |> Enum.reduce({0, 0}, fn {species_id, compound_id}, {derived, promoted} ->
      case derive_candidate(species_id, compound_id, opts) do
        {:ok, %{promoted: true}} -> {derived + 1, promoted + 1}
        {:ok, _} -> {derived + 1, promoted}
      end
    end)
  end

  # Upsert on the natural key, replacing only the evidence fields — status, notes, and
  # review sources-of-truth are preserved across re-derivation.
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
      conflict_target: [:foundemental_species_id, :compound_id, :relationship_type],
      returning: true
    )
  end

  # Refresh the candidate's reference-study provenance to the current co-occurrence set.
  defp replace_candidate_studies(candidate_id, study_ids) do
    Repo.delete_all(
      from(cs in SpeciesCompoundCandidateStudy, where: cs.candidate_id == ^candidate_id)
    )

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(study_ids, fn study_id ->
        %{candidate_id: candidate_id, study_id: study_id, inserted_at: now, updated_at: now}
      end)

    if entries != [] do
      Repo.insert_all(SpeciesCompoundCandidateStudy, entries, on_conflict: :nothing)
    end

    :ok
  end

  defp maybe_auto_promote(%Candidate{status: "pending", evidence_score: score} = candidate, opts) do
    threshold = Keyword.get(opts, :threshold, promotion_threshold())

    cond do
      not (is_number(score) and score >= threshold) ->
        {:ok, %{candidate: candidate, promoted: false}}

      true ->
        case plausibility_gate(candidate, opts) do
          {:promote, candidate} ->
            {:ok, promoted} = do_promote(candidate, "literature")
            {:ok, %{candidate: promoted, promoted: true}}

          {:hold, candidate} ->
            {:ok, %{candidate: candidate, promoted: false}}
        end
    end
  end

  defp maybe_auto_promote(candidate, _opts), do: {:ok, %{candidate: candidate, promoted: false}}

  # ── Plausibility gate (the automated "reality check" on auto-promotion) ─────

  # Decide whether a ≥-threshold candidate may auto-promote into a curated fact:
  #   * compound curated `dietary`     → trusted, skip the LLM and promote;
  #   * compound curated `non_dietary` → never promote (defensive; also excluded
  #     from `evidence_pairs/0` upstream);
  #   * otherwise run the LLM judge ONCE (verdict cached on the candidate) — only a
  #     `:plausible` verdict promotes. `:implausible` / `:uncertain` / any judge
  #     error / no API key are fail-safe: hold the candidate `pending` for review.
  # Never raises: the judge is wrapped so an AI fault can't bubble into the
  # derivation worker and poison-pill the single-threaded `:imports` chain.
  defp plausibility_gate(candidate, opts) do
    if Keyword.get(opts, :skip_plausibility, false) do
      {:promote, candidate}
    else
      do_plausibility_gate(candidate, Repo.get(Compound, candidate.compound_id), opts)
    end
  end

  defp do_plausibility_gate(candidate, %Compound{dietary_relevance: "dietary"}, _opts),
    do: {:promote, candidate}

  defp do_plausibility_gate(candidate, %Compound{dietary_relevance: "non_dietary"}, _opts),
    do: {:hold, candidate}

  defp do_plausibility_gate(candidate, nil, _opts), do: {:hold, candidate}

  # Already judged — reuse the cached verdict instead of re-calling the model.
  defp do_plausibility_gate(%Candidate{plausibility_verdict: "plausible"} = candidate, _c, _opts),
    do: {:promote, candidate}

  defp do_plausibility_gate(%Candidate{plausibility_verdict: v} = candidate, _c, _opts)
       when v in ["implausible", "uncertain"],
       do: {:hold, candidate}

  defp do_plausibility_gate(candidate, compound, _opts) do
    species = Repo.get(FoundementalFoodSpecies, candidate.foundemental_species_id)
    studies = Repo.preload(candidate, :studies).studies

    case run_judge(species, compound, studies) do
      {:ok, %{verdict: verdict, reason: reason}} ->
        {:ok, candidate} = store_plausibility(candidate, verdict, reason)
        if verdict == :plausible, do: {:promote, candidate}, else: {:hold, candidate}

      {:error, _reason} ->
        # Fail-safe: don't cache, hold for review; a later derive can retry the judge.
        {:hold, candidate}
    end
  end

  defp run_judge(species, compound, studies) do
    judge = Application.get_env(:mehungry, :compound_plausibility_judge, CompoundPlausibility)
    judge.judge(species, compound, studies)
  rescue
    e ->
      Logger.warning("compound plausibility judge crashed: #{inspect(e)}")
      {:error, :judge_crashed}
  catch
    kind, reason ->
      Logger.warning("compound plausibility judge threw: #{inspect({kind, reason})}")
      {:error, :judge_threw}
  end

  defp store_plausibility(candidate, verdict, reason) do
    candidate
    |> Candidate.changeset(%{
      plausibility_verdict: to_string(verdict),
      plausibility_reason: reason,
      plausibility_checked_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    })
    |> Repo.update()
  end

  # ── Audit of already-promoted literature facts ──────────────────────────────
  #
  # The plausibility gate only guards *new* auto-promotions; facts promoted before
  # the gate existed were never judged. This audit re-runs the same judge over those
  # facts and, for implausible ones, records the verdict on the backing candidate so
  # they surface in the "Flagged facts" review list. It only FLAGS — never deletes; a
  # human decides via Undo or "Non-dietary".

  # Promoted `literature` candidates on `pending`-relevance compounds the judge has
  # never seen (`plausibility_verdict` is nil) — the pre-gate facts still to audit.
  defp facts_to_audit_query do
    from(c in Candidate,
      join: rel in SpeciesCompoundRelationship,
      on: rel.id == c.promoted_relationship_id,
      join: cmp in Compound,
      on: cmp.id == c.compound_id,
      where: c.status == "promoted" and is_nil(c.plausibility_verdict),
      where: rel.source == "literature" and cmp.dietary_relevance == "pending"
    )
  end

  @doc "How many promoted literature facts still need a plausibility audit."
  def count_promoted_facts_to_audit,
    do: Repo.aggregate(facts_to_audit_query(), :count, :id)

  @doc "A batch of un-audited promoted literature facts (with assocs), newest first."
  def list_promoted_facts_to_audit(limit) do
    Repo.all(
      from(c in facts_to_audit_query(),
        order_by: [desc: c.id],
        limit: ^limit,
        preload: [:species, :compound, :studies]
      )
    )
  end

  @doc """
  Re-judge one promoted fact's `(species, compound)` and store the verdict on its
  candidate. Never promotes/deletes — audit only records the verdict. Returns
  `{:ok, verdict}` or `{:error, reason}` (judge unavailable: leaves it un-audited).
  """
  def audit_promoted_fact(%Candidate{} = candidate) do
    candidate = Repo.preload(candidate, [:species, :compound, :studies])

    case run_judge(candidate.species, candidate.compound, candidate.studies) do
      {:ok, %{verdict: verdict, reason: reason}} ->
        {:ok, _} = store_plausibility(candidate, verdict, reason)
        {:ok, verdict}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Audit up to `limit` un-audited promoted literature facts. Returns
  `{audited, flagged}` — `audited` counts those that got a verdict this pass (judge
  errors are skipped for a later pass), `flagged` those judged `implausible`.
  """
  def audit_promoted_facts_batch(limit) do
    list_promoted_facts_to_audit(limit)
    |> Enum.reduce({0, 0}, fn candidate, {audited, flagged} ->
      case audit_promoted_fact(candidate) do
        {:ok, :implausible} -> {audited + 1, flagged + 1}
        {:ok, _} -> {audited + 1, flagged}
        {:error, _} -> {audited, flagged}
      end
    end)
  end

  @doc "Promoted facts the audit judged `implausible` — the review queue for existing facts."
  def list_flagged_facts(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Repo.all(
      from(c in Candidate,
        join: rel in SpeciesCompoundRelationship,
        on: rel.id == c.promoted_relationship_id,
        where: c.status == "promoted" and c.plausibility_verdict == "implausible",
        order_by: [desc: c.id],
        limit: ^limit,
        preload: [:species, :compound]
      )
    )
  end

  @doc "Enqueue the fact-audit worker to re-judge un-audited promoted literature facts."
  def enqueue_fact_audit do
    %{}
    |> Mehungry.ObanWorkers.CompoundFactAuditWorker.new()
    |> Oban.insert()
  end

  # ── Promotion / review ────────────────────────────────────────────────────

  @doc """
  Promote a candidate into a curated `SpeciesCompoundRelationship` fact and mark it
  `promoted`. Idempotent — the fact upsert and the status flip both no-op on
  re-promote. Accepts a struct or an id.
  """
  def promote_candidate(%Candidate{} = candidate),
    do: do_promote(candidate, promotion_source(candidate))

  def promote_candidate(id), do: promote_candidate(get_candidate!(id))

  defp do_promote(%Candidate{} = candidate, source) do
    {:ok, relationship} =
      SpeciesCompounds.upsert_species_relationship(%{
        foundemental_species_id: candidate.foundemental_species_id,
        compound_id: candidate.compound_id,
        relationship_type: candidate.relationship_type,
        source: source,
        confidence: candidate.evidence_score,
        notes: promotion_note(candidate)
      })

    freeze_relationship_studies(relationship.id, candidate.id)

    candidate
    |> Candidate.changeset(%{status: "promoted", promoted_relationship_id: relationship.id})
    |> Repo.update()
  end

  # Copy the candidate's co-occurrence reference studies onto the curated fact as
  # frozen provenance. Idempotent (`on_conflict: :nothing`); never rewritten by
  # re-derivation, so the fact keeps citing the papers it was promoted from.
  defp freeze_relationship_studies(relationship_id, candidate_id) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    study_ids =
      Repo.all(
        from(cs in SpeciesCompoundCandidateStudy,
          where: cs.candidate_id == ^candidate_id,
          select: cs.study_id
        )
      )

    entries =
      Enum.map(study_ids, fn study_id ->
        %{relationship_id: relationship_id, study_id: study_id, inserted_at: now, updated_at: now}
      end)

    if entries != [] do
      Repo.insert_all(SpeciesCompoundRelationshipStudy, entries, on_conflict: :nothing)
    end

    :ok
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
  Undo a promoted fact: delete the curated `SpeciesCompoundRelationship` and mark the
  candidate that promoted it `rejected`, so re-derivation won't re-promote it. Safe for
  a manually-created relationship with no backing candidate.
  """
  def unpromote_relationship(relationship_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(c in Candidate, where: c.promoted_relationship_id == ^relationship_id)
    |> Repo.update_all(set: [status: "rejected", promoted_relationship_id: nil, updated_at: now])

    case Repo.get(SpeciesCompoundRelationship, relationship_id) do
      nil -> {:ok, nil}
      rel -> Repo.delete(rel)
    end
  end

  @doc """
  Insert a human-asserted candidate (source `manual`) for a `(species, compound)` pair.
  `attrs` may carry `:relationship_type`, `:evidence_score`, `:notes`. Idempotent on the
  natural key.
  """
  def import_manual_candidate(species_id, compound_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new()
      |> Map.merge(%{
        foundemental_species_id: species_id,
        compound_id: compound_id,
        sources: ["manual"]
      })
      |> Map.put_new(:relationship_type, "contains")
      |> Map.put_new(:status, "pending")

    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:notes, :updated_at]},
      conflict_target: [:foundemental_species_id, :compound_id, :relationship_type],
      returning: true
    )
  end

  # ── Non-dietary compounds (the curatable dietary-relevance gate) ─────────────

  # Seed list of assay reagents / solvents / non-specific class terms PubTator
  # extracts as "chemicals" that must never become dietary facts. This is only the
  # migration/backfill seed — the source of truth is now each compound's
  # `dietary_relevance` attribute. Overridable via `config :mehungry, :non_dietary_compounds`.
  @default_non_dietary ~w(DPPH ABTS TPTZ Trolox FRAP ORAC)

  @doc "Seed names of non-dietary compounds (backfill source for `dietary_relevance`)."
  def non_dietary_compound_names do
    Application.get_env(:mehungry, :non_dietary_compounds, @default_non_dietary)
  end

  @doc "Compound ids flagged `non_dietary` — the curated exclusion set."
  def blocklisted_compound_ids do
    Repo.all(from(c in Compound, where: c.dietary_relevance == "non_dietary", select: c.id))
  end

  @doc """
  Remove any candidates and curated relationships for `non_dietary` compounds. Runs at
  the start of each derivation so a newly-flagged compound (e.g. Ethanol) is purged.
  Returns `{relationships_deleted, candidates_deleted}`.
  """
  def purge_non_dietary do
    case blocklisted_compound_ids() do
      [] ->
        {0, 0}

      ids ->
        {rels, _} =
          Repo.delete_all(from(r in SpeciesCompoundRelationship, where: r.compound_id in ^ids))

        {cands, _} = Repo.delete_all(from(c in Candidate, where: c.compound_id in ^ids))
        {rels, cands}
    end
  end

  @doc "Deprecated alias for `purge_non_dietary/0`."
  def purge_blocklisted, do: purge_non_dietary()

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
        preload: [:species, :compound, :studies],
        limit: ^limit,
        offset: ^offset
      )
    )
  end

  def list_candidates_for_species(species_id) do
    Repo.all(
      from(c in Candidate,
        where: c.foundemental_species_id == ^species_id,
        order_by: [desc: c.evidence_score, asc: c.id],
        preload: [:compound, :studies]
      )
    )
  end

  @doc "The reference studies a candidate was derived from, newest first."
  def list_candidate_studies(candidate_id) do
    Repo.all(
      from(cs in SpeciesCompoundCandidateStudy,
        join: s in assoc(cs, :study),
        where: cs.candidate_id == ^candidate_id,
        order_by: [desc: s.id],
        select: s
      )
    )
  end

  def get_candidate!(id),
    do: Repo.get!(Candidate, id) |> Repo.preload([:species, :compound, :studies])

  @doc "Coverage snapshot for the progress bar: pairs with a candidate row / all evidence pairs."
  def candidate_derivation_progress do
    total = count_evidence_pairs()
    processed = Repo.aggregate(Candidate, :count, :id)
    %{processed: min(processed, total), total: total}
  end

  # ── Pipeline entry point ──────────────────────────────────────────────────

  @doc "Open a tracked derivation run and enqueue the first batch. Returns `{:ok, run}`."
  def enqueue_candidate_derivation do
    # Clear out any facts/candidates for newly-flagged non-dietary compounds first.
    purge_non_dietary()
    run = Mehungry.Food.CandidateDerivationRuns.start_run()

    {:ok, _job} =
      %{"run_id" => run.id}
      |> Mehungry.ObanWorkers.CompoundCandidateDerivationWorker.new()
      |> Oban.insert()

    {:ok, run}
  end
end
