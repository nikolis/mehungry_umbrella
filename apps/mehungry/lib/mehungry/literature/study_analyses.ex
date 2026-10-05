defmodule Mehungry.Literature.StudyAnalyses do
  @moduledoc """
  Persists and reconciles the `mehungry_extractor` `/analyze` response
  (see `mehungry_extractor/docs/api.md`) at the **per-paper** grain.

  `store_analysis_response/1` takes a full `/analyze` response map and, for each
  paper, upserts one `StudyAnalysis` row keyed on the paper's `ScientificStudy`
  (resolved by PMID). The endpoint returns the normalized **claim** layer
  (`paper_claims[]` → `claims_list[]`, keyed on `claim_id`); that list is what a
  row stores. Reconciliation is an upsert with content diffing: a new paper is
  inserted, a paper whose extracted content changed (by `content_hash`) is
  updated in place, an identical one is left untouched, and a PMID with no stored
  study is skipped (there is no row to key). The whole batch runs in one
  transaction.
  """

  import Ecto.Query, warn: false

  alias Mehungry.Repo
  alias Mehungry.Literature.{ScientificStudy, StudyAnalysis, StudyCondition}

  @doc """
  Upsert one `StudyAnalysis` per paper in the `/analyze` `response`, reconciling
  against what is already stored. Returns
  `{:ok, %{inserted: n, updated: n, unchanged: n, skipped: n}}`.
  """
  def store_analysis_response(response) when is_map(response) do
    run = response["run"] || %{}
    papers = papers_by_pmid(response)

    Repo.transaction(fn ->
      Enum.reduce(papers, %{inserted: 0, updated: 0, unchanged: 0, skipped: 0}, fn {pmid, paper},
                                                                                   acc ->
        outcome = reconcile_paper(pmid, paper, run)
        Map.update!(acc, outcome, &(&1 + 1))
      end)
    end)
  end

  @doc "The stored analysis for a study id, or nil."
  def get_analysis_by_study_id(study_id),
    do: Repo.get_by(StudyAnalysis, study_id: study_id)

  # Curation positions a claim can be assigned. Only `food_related` feeds the
  # suggestion/rule derivation (see `Mehungry.Health.ClaimRules`); an unassigned
  # claim (no `position` key) counts as none of them.
  @positions ~w(food_related general_science wrong ignore)

  @doc "The valid claim curation positions."
  def claim_positions, do: @positions

  @doc """
  Set the curation `position` on a single claim (by `claim_id`) within a study's
  stored analysis. Claims live in the `claims` jsonb array, so this rewrites that
  one entry in place. A blank/unknown position clears the assignment (removes the
  key). The content hash is left untouched (it ignores `position`), so a later
  re-analysis won't clobber the curation.
  """
  def set_claim_position(study_id, claim_id, position) do
    position = normalize_position(position)

    case get_analysis_by_study_id(study_id) do
      nil ->
        {:error, :not_found}

      %StudyAnalysis{claims: claims} = analysis ->
        updated =
          Enum.map(claims || [], fn claim ->
            cond do
              claim["claim_id"] != claim_id -> claim
              is_nil(position) -> Map.delete(claim, "position")
              true -> Map.put(claim, "position", position)
            end
          end)

        analysis
        |> StudyAnalysis.changeset(%{claims: updated})
        |> Repo.update()
    end
  end

  defp normalize_position(position) when position in @positions, do: position
  defp normalize_position(_), do: nil

  @doc """
  The stored analyses for every paper a condition was crawled for (via
  `study_conditions`), `:study` preloaded (for pmid/title). One row per study,
  deduped — a paper linked under several search terms yields a single analysis.
  """
  def analyses_for_condition(condition_id) do
    StudyAnalysis
    |> join(:inner, [a], l in StudyCondition, on: l.study_id == a.study_id)
    |> where([_a, l], l.condition_id == ^condition_id)
    |> preload(:study)
    |> Repo.all()
    |> Enum.uniq_by(& &1.study_id)
  end

  @doc "The subset of `study_ids` that already have a stored analysis, as a MapSet."
  def analyzed_study_ids(study_ids) when is_list(study_ids) do
    StudyAnalysis
    |> where([a], a.study_id in ^study_ids)
    |> select([a], a.study_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  The subset of `study_ids` whose stored analysis found the paper **not usable** —
  its `source_type` is anything other than `"open_access"` (`abstract`, `none`, or
  unknown). Only full-text open-access papers can be extracted reliably for now,
  so these are flagged and barred from (re-)analysis. Returned as a MapSet.
  Un-analyzed studies are absent (their source type isn't known until analyzed).
  """
  def unusable_study_ids(study_ids) when is_list(study_ids) do
    StudyAnalysis
    |> where([a], a.study_id in ^study_ids)
    |> where([a], is_nil(a.source_type) or a.source_type != "open_access")
    |> select([a], a.study_id)
    |> Repo.all()
    |> MapSet.new()
  end

  # ── Reconciliation ─────────────────────────────────────────────────────────

  defp reconcile_paper(pmid, paper, run) do
    case resolve_study(pmid) do
      nil ->
        :skipped

      %ScientificStudy{id: study_id} ->
        attrs = build_attrs(study_id, paper, run)

        case get_analysis_by_study_id(study_id) do
          nil ->
            {:ok, _} = insert_analysis(attrs)
            :inserted

          %StudyAnalysis{content_hash: hash} = existing ->
            if hash == attrs.content_hash do
              :unchanged
            else
              # Content changed → overwrite the claims, but carry the admin's
              # curation (`position`) forward so a re-analysis doesn't wipe it.
              attrs = %{attrs | claims: carry_positions(attrs.claims, existing.claims || [])}
              {:ok, _} = update_analysis(existing, attrs)
              :updated
            end
        end
    end
  end

  defp insert_analysis(attrs) do
    %StudyAnalysis{}
    |> StudyAnalysis.changeset(attrs)
    |> Repo.insert()
  end

  defp update_analysis(existing, attrs) do
    existing
    |> StudyAnalysis.changeset(attrs)
    |> Repo.update()
  end

  # ── Attrs + hashing ────────────────────────────────────────────────────────

  defp build_attrs(study_id, paper, run) do
    claims = paper["claims_list"] || []

    attrs = %{
      study_id: study_id,
      status: paper["status"] || "included",
      error: paper["error"],
      paper_title: paper["paper_title"] || paper["title"],
      publication_year: paper["publication_year"],
      source_type: paper["source_type"],
      study_design: paper["study_design"],
      sample_size: paper["sample_size"],
      funder_types: paper["funder_types"] || [],
      funding_independence: paper["funding_independence"],
      n_claims: paper["n_claims"],
      concept_count: paper["concept_count"],
      cohesion_score: paper["cohesion_score"],
      claims: claims,
      run: run,
      analyzed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Map.put(attrs, :content_hash, content_hash(attrs))
  end

  @doc """
  A stable SHA-256 digest of a paper's meaningful extracted content — the claims
  (each reduced to `claim_id|predicate|polarity|certainty`, sorted) plus the
  paper-level facts. Independent of JSON key ordering, and still sensitive to a
  polarity flip that leaves `claim_id` unchanged.
  """
  def content_hash(attrs) do
    claims_part =
      (attrs.claims || [])
      |> Enum.map(fn c ->
        Enum.join(
          [c["claim_id"], c["predicate"], c["polarity"], c["certainty"]],
          "|"
        )
      end)
      |> Enum.sort()
      |> Enum.join("\n")

    facts_part =
      Enum.join(
        [
          attrs.status,
          attrs.study_design,
          attrs.sample_size,
          attrs.n_claims,
          attrs.concept_count,
          attrs.cohesion_score,
          attrs.funding_independence
        ],
        "|"
      )

    :crypto.hash(:sha256, facts_part <> "\n" <> claims_part)
    |> Base.encode16(case: :lower)
  end

  # ── Curation carry-forward ──────────────────────────────────────────────────

  @doc """
  Preserve the admin's per-claim curation (`position`) across a re-analysis that
  changed a paper's content. Each freshly extracted claim inherits a prior
  `position` matched first by `claim_id` (stable when the claim is unchanged),
  then by a normalized `subject|predicate|object|polarity` key (so a claim whose
  content-addressed id shifted still keeps its state). New claims with no prior
  match are left unassigned.
  """
  def carry_positions(new_claims, old_claims) do
    positioned = Enum.filter(old_claims || [], & &1["position"])
    by_id = Map.new(positioned, &{&1["claim_id"], &1["position"]})
    by_key = Map.new(positioned, &{claim_key(&1), &1["position"]})

    Enum.map(new_claims || [], fn claim ->
      cond do
        claim["position"] -> claim
        pos = by_id[claim["claim_id"]] -> Map.put(claim, "position", pos)
        pos = by_key[claim_key(claim)] -> Map.put(claim, "position", pos)
        true -> claim
      end
    end)
  end

  # A content key for matching a claim across a re-analysis when its claim_id
  # changed: the resolved endpoints + predicate + polarity, normalized.
  defp claim_key(claim) do
    [
      claim["subject_name"] || claim["subject_label"] || claim["subject_text"],
      claim["predicate"],
      claim["object_name"] || claim["object_label"] || claim["object_text"],
      claim["polarity"]
    ]
    |> Enum.map_join("|", &normalize_key_part/1)
  end

  defp normalize_key_part(nil), do: ""
  defp normalize_key_part(part) when is_binary(part), do: part |> String.trim() |> String.downcase()
  defp normalize_key_part(part), do: to_string(part)

  # ── PMID → study resolution ────────────────────────────────────────────────

  # Merge the per-paper facts (`papers[]`) with the per-paper claims
  # (`paper_claims[]`) by PMID. `papers[]` covers every requested paper
  # (incl. errors); `paper_claims[]` adds `claims_list` for the ones that
  # extracted.
  defp papers_by_pmid(response) do
    facts = Map.new(response["papers"] || [], fn p -> {to_string(p["pmid"]), p} end)

    Enum.reduce(response["paper_claims"] || [], facts, fn pc, acc ->
      key = to_string(pc["pmid"])
      Map.update(acc, key, pc, fn existing -> Map.merge(existing, pc) end)
    end)
  end

  defp resolve_study(pmid) do
    case parse_pmid(pmid) do
      nil -> nil
      int -> Repo.get_by(ScientificStudy, pmid: int)
    end
  end

  # PMIDs arrive as strings (possibly "pmid:NNNN"); ScientificStudy.pmid is an
  # integer. Non-numeric input resolves to nil (→ skipped).
  defp parse_pmid(pmid) when is_integer(pmid), do: pmid

  defp parse_pmid(pmid) when is_binary(pmid) do
    case pmid |> String.trim() |> String.trim_leading("pmid:") |> Integer.parse() do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_pmid(_), do: nil
end
