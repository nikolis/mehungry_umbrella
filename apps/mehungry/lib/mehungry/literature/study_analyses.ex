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
  alias Mehungry.Health.Condition
  alias Mehungry.Literature.{
    JournalAuthority,
    ResearchType,
    ScientificStudy,
    StudyAnalysis,
    StudyCondition,
    StudyFullText
  }

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

  # Minimum pg_trgm word_similarity for a condition to match the research-search
  # box — mirrors the fuzzy-search threshold used in `Food.IngredientSearch`.
  @fuzzy_threshold 0.3

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

  @doc """
  The nutritionist research-search **catalog**: every `Health.Condition` that has
  at least one stored, non-error `StudyAnalysis` (reached via `study_conditions`),
  with its distinct analyzed-paper `study_count`, ordered by count desc then name.

  Optional `search` does a **fuzzy** match on the condition name — pg_trgm
  `word_similarity` (accent-insensitive), so typos and reordered words still
  match ("colitis ulcerativ" → "Ulcerative Colitis"); a plain substring hit is
  always kept too. Results are then ranked by similarity. This is the
  curated-catalog surface — a condition with no digested research never appears,
  so search only ever offers conditions that have results.
  """
  def conditions_with_research(search \\ nil) do
    base =
      Condition
      |> join(:inner, [c], l in StudyCondition, on: l.condition_id == c.id)
      |> join(:inner, [c, l], a in StudyAnalysis,
        on: a.study_id == l.study_id and a.status != "error"
      )
      |> group_by([c], c.id)
      |> select([c, _l, a], %{condition: c, study_count: count(a.study_id, :distinct)})

    base
    |> search_and_order(search)
    |> Repo.all()
  end

  @doc """
  How many distinct `Health.Condition`s have at least one stored, non-error
  `StudyAnalysis` — the honest "conditions with digested research" headline figure.
  A single cheap aggregate (one row), returns `0` on empty data, never `nil`.
  """
  def count_conditions_with_research do
    StudyCondition
    |> join(:inner, [l], a in StudyAnalysis,
      on: a.study_id == l.study_id and a.status != "error"
    )
    |> select([l], count(l.condition_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  How many distinct papers have a stored, non-error `StudyAnalysis` — the honest
  "papers digested" figure (distinct from `Literature.count_studies/0`, which counts
  everything *crawled*). One cheap aggregate, returns `0` on empty data, never `nil`.
  """
  def count_analyzed_studies do
    StudyAnalysis
    |> where([a], a.status != "error")
    |> select([a], count(a.study_id, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  The nutritionist research-search **landing list**: **every** `Health.Condition`,
  each with its distinct non-error analyzed-paper `study_count` (0 when none has
  been digested yet). Unlike `conditions_with_research/1` this does not hide
  no-research conditions — the landing is a browser over the whole condition
  vocabulary; opening one with `study_count == 0` just shows the "no digested
  research yet" state on the results page.

  Default order puts conditions **with research first** (count desc) then name;
  `search` applies the same fuzzy name match + similarity ranking as
  `conditions_with_research/1`.
  """
  def conditions_for_search(search \\ nil) do
    base =
      Condition
      |> join(:left, [c], l in StudyCondition, on: l.condition_id == c.id)
      |> join(:left, [c, l], a in StudyAnalysis,
        on: a.study_id == l.study_id and a.status != "error"
      )
      |> group_by([c], c.id)
      |> select([c, _l, a], %{condition: c, study_count: count(a.study_id, :distinct)})

    base
    |> search_and_order(search)
    |> Repo.all()
  end

  defp search_and_order(query, search) when is_binary(search) do
    case String.trim(search) do
      "" ->
        default_order(query)

      term ->
        query
        |> where(
          [c],
          ilike(c.name, ^"%#{term}%") or
            fragment(
              "word_similarity(unaccent(?), unaccent(?)) > ?",
              ^term,
              c.name,
              ^@fuzzy_threshold
            )
        )
        |> order_by([c, _l, a],
          desc: fragment("word_similarity(unaccent(?), unaccent(?))", ^term, c.name),
          desc: count(a.study_id, :distinct),
          asc: c.name
        )
    end
  end

  defp search_and_order(query, _), do: default_order(query)

  defp default_order(query) do
    order_by(query, [c, _l, a], desc: count(a.study_id, :distinct), asc: c.name)
  end

  @doc """
  The condition's digested research, **grouped by research type** for the results
  page. Reuses `analyses_for_condition/1`, drops `error` rows, assigns each paper a
  `Mehungry.Literature.ResearchType` bucket, and returns the non-empty buckets in
  evidence-hierarchy order:

      [%{key: :systematic_review, label: "…", analyses: [%StudyAnalysis{study: …}]}, …]

  Within a bucket, papers are sorted most-recent then largest-sample first
  (publication_year desc, sample_size desc, nils last). Claim-level visibility
  (hiding `wrong`/`ignore`) is left to the caller's render.
  """
  def grouped_research_for_condition(condition_id) do
    analyses =
      condition_id
      |> analyses_for_condition()
      |> Enum.reject(&(&1.status == "error"))

    outlines = full_text_outlines(Enum.map(analyses, & &1.study_id))

    analyses
    |> Enum.map(fn a ->
      case Map.fetch(outlines, a.study_id) do
        {:ok, outline} -> %{a | has_full_text: true, outline: outline}
        :error -> %{a | has_full_text: false, outline: []}
      end
    end)
    |> Enum.group_by(&ResearchType.bucket(&1.study_design))
    |> Enum.map(fn {key, analyses} ->
      %{key: key, label: ResearchType.label(key), analyses: Enum.sort_by(analyses, &sort_key/1)}
    end)
    |> Enum.sort_by(&ResearchType.order(&1.key))
  end

  # For the `study_ids` that have a stored, non-empty full-text outline, a map
  # `study_id => [%{"id" => section_id, "title" => …}]` — the lightweight section
  # table-of-contents the results card deep-links into the reader. One query
  # (avoids an N+1 over the cards); only section titles are read off the jsonb.
  defp full_text_outlines([]), do: %{}

  defp full_text_outlines(study_ids) do
    StudyFullText
    |> where([f], f.study_id in ^study_ids)
    |> where([f], fragment("jsonb_array_length(coalesce(?, '[]'::jsonb)) > 0", f.sections))
    |> select([f], {f.study_id, f.sections})
    |> Repo.all()
    |> Map.new(fn {study_id, sections} -> {study_id, outline_from_sections(sections)} end)
  end

  defp outline_from_sections(sections) do
    sections
    |> Enum.with_index()
    |> Enum.map(fn {sec, i} ->
      title = sec["title"]
      %{"id" => sec["section_id"], "title" => if(title in [nil, ""], do: "Section #{i + 1}", else: title)}
    end)
  end

  @doc """
  The data for the in-app research **reader** of one study: its `StudyFullText`
  (the structured `sections`) with the study's **visible** claims (the `wrong`/
  `ignore` curation hidden) folded into each owning paragraph as highlight spans.

  Returns `nil` when the study has no stored full-text outline. Otherwise:

      %{
        study: %ScientificStudy{},
        analysis: %StudyAnalysis{} | nil,
        sections: [section_map, …],              # verbatim from the extractor
        spans_by_paragraph: %{paragraph_id => [span]}
      }

  where a `span` is `%{start: int, end: int, polarity: String, quoted_text: String,
  claim_id: String}` with `start`/`end` made **paragraph-relative** (so the reader
  can slice `paragraph.text` directly). Spans with no resolvable paragraph/offset
  are dropped.
  """
  def full_text_for_reader(study_id) do
    case Repo.get_by(StudyFullText, study_id: study_id) do
      %StudyFullText{sections: [_ | _] = sections} = full_text ->
        study = Repo.get(ScientificStudy, study_id)
        analysis = get_analysis_by_study_id(study_id)
        claims = visible_claims(analysis)

        %{
          study: study,
          analysis: analysis,
          sections: sections,
          spans_by_paragraph: spans_by_paragraph(claims, paragraph_offsets(sections)),
          full_text: full_text
        }

      _ ->
        nil
    end
  end

  defp visible_claims(%StudyAnalysis{claims: claims}) when is_list(claims),
    do: Enum.reject(claims, &(&1["position"] in ~w(wrong ignore)))

  defp visible_claims(_), do: []

  # paragraph_id => its absolute start_char (to make evidence offsets relative).
  defp paragraph_offsets(sections) do
    for sec <- sections, par <- sec["paragraphs"] || [], into: %{} do
      {par["paragraph_id"], par["start_char"]}
    end
  end

  # Fold each visible claim's evidence spans onto their owning paragraph, as
  # paragraph-relative {start, end} highlight ranges.
  defp spans_by_paragraph(claims, par_starts) do
    claims
    |> Enum.flat_map(fn claim ->
      for ev <- claim["evidence"] || [],
          par_id = ev["paragraph_id"],
          par_start = par_starts[par_id],
          is_integer(ev["start_char"]),
          is_integer(ev["end_char"]) do
        {par_id,
         %{
           start: ev["start_char"] - par_start,
           end: ev["end_char"] - par_start,
           polarity: claim["polarity"],
           quoted_text: ev["quoted_text"],
           claim_id: claim["claim_id"]
         }}
      end
    end)
    |> Enum.group_by(fn {par_id, _span} -> par_id end, fn {_par_id, span} -> span end)
  end

  # MEDLINE-indexed first, then most-recent, then largest-sample; nils last.
  # (Negating is fine for the integer fields; a nil becomes a large sentinel so
  # it sorts to the end.)
  defp sort_key(%StudyAnalysis{publication_year: y, sample_size: n, study: study}) do
    {JournalAuthority.rank(study), -(y || -99_999), -(n || 0)}
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

  @doc """
  The subset of `study_ids` whose stored analysis found the paper **definitely has
  no full text** — `source_type` is a *known* `"abstract"` or `"none"`. Narrower
  than `unusable_study_ids/1`: a `nil` (unknown) source type is **not** included,
  because it may well be open-access (e.g. analyzed by an older extractor that
  didn't record the source type) and is worth re-analyzing. Used by the research
  ingestion's `force` path so a re-run can backfill `sections` onto those unknowns.
  """
  def known_abstract_study_ids(study_ids) when is_list(study_ids) do
    StudyAnalysis
    |> where([a], a.study_id in ^study_ids)
    |> where([a], a.source_type in ["abstract", "none"])
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
        # The enriched `/analyze` response carries the paper's structured
        # full-text outline (open-access papers only); persist it as the study's
        # `StudyFullText` independent of the claims reconcile outcome (sections can
        # arrive on an otherwise-unchanged re-analysis, e.g. after the extractor is
        # upgraded). Abstract-only papers carry no sections → left untouched.
        maybe_store_full_text(study_id, paper)

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

  # Upsert the study's structured full text from the `/analyze` payload's
  # `sections` outline. A no-op unless the paper carries a non-empty list (so
  # abstract-only papers and a not-yet-upgraded extractor leave full text alone).
  # `body` is reconstructed from the paragraph slices (the changeset requires it).
  defp maybe_store_full_text(study_id, paper) do
    case paper["sections"] do
      [_ | _] = sections ->
        %StudyFullText{}
        |> StudyFullText.changeset(%{
          study_id: study_id,
          source: "mehungry_extractor",
          sections: sections,
          body: body_from_sections(sections),
          retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert(
          on_conflict: {:replace_all_except, [:id, :inserted_at]},
          conflict_target: [:study_id]
        )

      _ ->
        :noop
    end
  end

  # Concatenate the paragraph texts in document order, blank-line separated.
  defp body_from_sections(sections) do
    sections
    |> Enum.flat_map(fn sec -> Enum.map(sec["paragraphs"] || [], & &1["text"]) end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
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
          # `source_type` is part of the hash so a re-analysis that newly resolves
          # a paper's source (e.g. nil → "open_access", from an upgraded extractor)
          # counts as changed and the row is updated — otherwise the stale source
          # would stick and the paper would be re-targeted on every force run.
          attrs.source_type,
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
