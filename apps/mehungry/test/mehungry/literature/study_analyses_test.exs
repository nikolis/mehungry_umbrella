defmodule Mehungry.Literature.StudyAnalysesTest do
  use Mehungry.DataCase, async: true

  alias Mehungry.Literature
  alias Mehungry.Literature.StudyAnalysis

  # A minimal `/analyze` response (mirrors `Mehungry.Extractor.ClientStub`'s shape)
  # for `pmid`, with the given claim list and `source_type` (default open_access).
  defp response(pmid, claims, source_type \\ "open_access") do
    %{
      "run" => %{"synthesis_version" => "0.1.0"},
      "requested_pmids" => [to_string(pmid)],
      "included_pmids" => [to_string(pmid)],
      "papers" => [
        %{
          "pmid" => to_string(pmid),
          "status" => "included",
          "title" => "Paper #{pmid}",
          "source_type" => source_type,
          "n_claims" => length(claims),
          "concept_count" => 3,
          "cohesion_score" => 0.8
        }
      ],
      "paper_claims" => [
        %{
          "pmid" => to_string(pmid),
          "paper_title" => "Paper #{pmid}",
          "claims_list" => claims
        }
      ],
      "warnings" => []
    }
  end

  defp claim(id, predicate, polarity) do
    %{
      "claim_id" => id,
      "predicate" => predicate,
      "polarity" => polarity,
      "certainty" => "asserted",
      "subject_label" => "Dietary fiber",
      "object_label" => "Remission"
    }
  end

  test "inserts a per-paper row on first store" do
    {:ok, study} = Literature.upsert_study(%{pmid: 111_001, title: "Fiber"})

    assert {:ok, %{inserted: 1, updated: 0, unchanged: 0, skipped: 0}} =
             Literature.store_analysis_response(response(111_001, [claim("c1", "improves", "positive")]))

    analysis = Literature.get_analysis_by_study_id(study.id)
    assert %StudyAnalysis{status: "included", n_claims: 1} = analysis
    assert [%{"claim_id" => "c1"}] = analysis.claims
    assert analysis.run["synthesis_version"] == "0.1.0"
  end

  test "re-storing identical content is unchanged" do
    {:ok, _study} = Literature.upsert_study(%{pmid: 111_002, title: "Fiber"})
    resp = response(111_002, [claim("c1", "improves", "positive")])

    assert {:ok, %{inserted: 1}} = Literature.store_analysis_response(resp)
    assert {:ok, %{inserted: 0, updated: 0, unchanged: 1}} = Literature.store_analysis_response(resp)
  end

  test "updates the row when claims change (polarity flip, same claim_id)" do
    {:ok, study} = Literature.upsert_study(%{pmid: 111_003, title: "Fiber"})

    assert {:ok, %{inserted: 1}} =
             Literature.store_analysis_response(response(111_003, [claim("c1", "improves", "positive")]))

    assert {:ok, %{updated: 1, unchanged: 0}} =
             Literature.store_analysis_response(response(111_003, [claim("c1", "improves", "negative")]))

    analysis = Literature.get_analysis_by_study_id(study.id)
    assert [%{"polarity" => "negative"}] = analysis.claims
  end

  test "re-analysis carries a claim's position forward by claim_id (content changed)" do
    {:ok, study} = Literature.upsert_study(%{pmid: 111_050, title: "Fiber"})

    {:ok, _} =
      Literature.store_analysis_response(response(111_050, [claim("c1", "improves", "positive")]))

    {:ok, _} = Literature.set_claim_position(study.id, "c1", "food_related")

    # Re-analyze with the same claim_id but a changed polarity (new content_hash).
    assert {:ok, %{updated: 1}} =
             Literature.store_analysis_response(response(111_050, [claim("c1", "improves", "negative")]))

    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert [%{"polarity" => "negative", "position" => "food_related"}] = claims
  end

  test "re-analysis carries position forward by subject/predicate/object when claim_id changes" do
    {:ok, study} = Literature.upsert_study(%{pmid: 111_051, title: "Fiber"})

    {:ok, _} =
      Literature.store_analysis_response(response(111_051, [claim("old-id", "improves", "positive")]))

    {:ok, _} = Literature.set_claim_position(study.id, "old-id", "food_related")

    # Same subject/predicate/object/polarity, but the content-addressed id shifted,
    # and n_claims context differs enough to change the hash → updated.
    assert {:ok, %{updated: 1}} =
             Literature.store_analysis_response(
               response(111_051, [
                 claim("new-id", "improves", "positive"),
                 claim("c2", "reduces", "negative")
               ])
             )

    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert Enum.find(claims, &(&1["claim_id"] == "new-id"))["position"] == "food_related"
    assert Enum.find(claims, &(&1["claim_id"] == "c2"))["position"] == nil
  end

  test "re-analysis leaves a genuinely new claim unassigned" do
    {:ok, study} = Literature.upsert_study(%{pmid: 111_052, title: "Fiber"})

    {:ok, _} =
      Literature.store_analysis_response(response(111_052, [claim("c1", "improves", "positive")]))

    {:ok, _} = Literature.set_claim_position(study.id, "c1", "food_related")

    {:ok, _} =
      Literature.store_analysis_response(
        response(111_052, [
          claim("c1", "improves", "positive"),
          claim("c9", "worsens", "positive")
        ])
      )

    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert Enum.find(claims, &(&1["claim_id"] == "c1"))["position"] == "food_related"
    assert Enum.find(claims, &(&1["claim_id"] == "c9"))["position"] == nil
  end

  test "skips a PMID with no stored ScientificStudy" do
    # 999999 was never upserted as a study.
    assert {:ok, %{inserted: 0, skipped: 1}} =
             Literature.store_analysis_response(response(999_999, [claim("c1", "improves", "positive")]))
  end

  test "set_claim_position sets the position on only the matching claim" do
    {:ok, study} = Literature.upsert_study(%{pmid: 112_020, title: "x"})

    Literature.store_analysis_response(
      response(112_020, [claim("c1", "improves", "positive"), claim("c2", "improves", "positive")])
    )

    {:ok, _} = Literature.set_claim_position(study.id, "c2", "food_related")

    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert Enum.find(claims, &(&1["claim_id"] == "c1"))["position"] == nil
    assert Enum.find(claims, &(&1["claim_id"] == "c2"))["position"] == "food_related"

    # An unknown/blank position clears the assignment.
    {:ok, _} = Literature.set_claim_position(study.id, "c2", "")
    claims = Literature.get_analysis_by_study_id(study.id).claims
    assert Enum.find(claims, &(&1["claim_id"] == "c2"))["position"] == nil
  end

  test "analyzed_study_ids returns only studies that have a stored analysis" do
    {:ok, s1} = Literature.upsert_study(%{pmid: 111_010, title: "a"})
    {:ok, s2} = Literature.upsert_study(%{pmid: 111_011, title: "b"})

    Literature.store_analysis_response(response(111_010, [claim("c1", "improves", "positive")]))

    ids = Literature.analyzed_study_ids([s1.id, s2.id])
    assert MapSet.member?(ids, s1.id)
    refute MapSet.member?(ids, s2.id)
  end

  test "unusable_study_ids flags analyzed studies that are not open_access" do
    {:ok, open} = Literature.upsert_study(%{pmid: 113_001, title: "open"})
    {:ok, abstract} = Literature.upsert_study(%{pmid: 113_002, title: "abstract"})
    {:ok, unanalyzed} = Literature.upsert_study(%{pmid: 113_003, title: "unanalyzed"})

    Literature.store_analysis_response(
      response(113_001, [claim("c1", "improves", "positive")], "open_access")
    )

    Literature.store_analysis_response(
      response(113_002, [claim("c1", "improves", "positive")], "abstract")
    )

    ids = Literature.unusable_study_ids([open.id, abstract.id, unanalyzed.id])

    # Only the analyzed, non-open-access paper is flagged.
    assert MapSet.member?(ids, abstract.id)
    refute MapSet.member?(ids, open.id)
    # An un-analyzed study has no known source type, so it is never flagged.
    refute MapSet.member?(ids, unanalyzed.id)
  end

  # ── Research-search catalog + grouping ──────────────────────────────────────

  defp link_condition(study, condition, term \\ "diet") do
    %Mehungry.Literature.StudyCondition{}
    |> Mehungry.Literature.StudyCondition.changeset(%{
      study_id: study.id,
      condition_id: condition.id,
      search_term: term
    })
    |> Mehungry.Repo.insert!()
  end

  # Store one analyzed paper for `pmid` with a given `study_design`
  # (+ optional :year/:n), linked to `condition`. Returns the study.
  defp analyzed_paper(pmid, condition, design, opts \\ []) do
    {:ok, study} =
      Literature.upsert_study(%{pmid: pmid, title: "P#{pmid}", citation_status: opts[:status]})

    link_condition(study, condition)

    resp = response(pmid, [claim("c1", "improves", "positive")])

    paper =
      resp["papers"]
      |> hd()
      |> Map.merge(%{
        "study_design" => design,
        "publication_year" => opts[:year],
        "sample_size" => opts[:n]
      })

    {:ok, _} = Literature.store_analysis_response(%{resp | "papers" => [paper]})
    study
  end

  describe "conditions_with_research/1" do
    test "lists only conditions with a non-error analysis, with distinct study counts" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})
      {:ok, ibs} = Mehungry.Health.create_condition(%{name: "IBS"})
      {:ok, _none} = Mehungry.Health.create_condition(%{name: "Gout"})

      analyzed_paper(211_001, uc, "randomized_controlled_trial")
      analyzed_paper(211_002, uc, "cohort")
      analyzed_paper(211_003, ibs, "review")

      catalog = Literature.conditions_with_research()
      by_name = Map.new(catalog, &{&1.condition.name, &1.study_count})

      assert by_name["Ulcerative Colitis"] == 2
      assert by_name["IBS"] == 1
      # A condition with no digested research never appears in the catalog.
      refute Map.has_key?(by_name, "Gout")
      # Ordered by study count desc.
      assert hd(catalog).condition.name == "Ulcerative Colitis"
    end

    test "search filters by condition name, case-insensitively; blank = no filter" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})
      {:ok, ibs} = Mehungry.Health.create_condition(%{name: "IBS"})
      analyzed_paper(211_010, uc, "cohort")
      analyzed_paper(211_011, ibs, "cohort")

      names = fn q -> Literature.conditions_with_research(q) |> Enum.map(& &1.condition.name) end

      assert names.("colitis") == ["Ulcerative Colitis"]
      # Tie on count (1 each) → name asc.
      assert names.("  ") == ["IBS", "Ulcerative Colitis"]
    end

    test "search is fuzzy: tolerates typos and reordered words, ranked by similarity" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})
      {:ok, crohns} = Mehungry.Health.create_condition(%{name: "Crohn's Disease"})
      analyzed_paper(211_020, uc, "cohort")
      analyzed_paper(211_021, crohns, "cohort")

      names = fn q -> Literature.conditions_with_research(q) |> Enum.map(& &1.condition.name) end

      # Typo'd term still finds the condition (substring ilike would miss this).
      assert names.("ulcerativ colitus") == ["Ulcerative Colitis"]
      # Reordered words match.
      assert names.("colitis ulcerative") == ["Ulcerative Colitis"]
      # Misspelled distinct condition resolves to the nearest match.
      assert names.("crohn") == ["Crohn's Disease"]
    end
  end

  describe "conditions_for_search/1" do
    test "lists every condition, research ones first (count desc) then name; blank = all" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})
      {:ok, ibs} = Mehungry.Health.create_condition(%{name: "IBS"})
      {:ok, _gout} = Mehungry.Health.create_condition(%{name: "Gout"})
      {:ok, _asthma} = Mehungry.Health.create_condition(%{name: "Asthma"})

      analyzed_paper(212_001, uc, "randomized_controlled_trial")
      analyzed_paper(212_002, uc, "cohort")
      analyzed_paper(212_003, ibs, "review")

      catalog = Literature.conditions_for_search()
      by_name = Map.new(catalog, &{&1.condition.name, &1.study_count})

      # No-research conditions appear too, with a 0 count.
      assert by_name["Gout"] == 0
      assert by_name["Asthma"] == 0
      assert by_name["Ulcerative Colitis"] == 2
      assert by_name["IBS"] == 1

      # Research first (count desc), then the 0-count rest alphabetically.
      assert Enum.map(catalog, & &1.condition.name) ==
               ["Ulcerative Colitis", "IBS", "Asthma", "Gout"]
    end

    test "fuzzy search filters the full list (incl. conditions with no research)" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "Ulcerative Colitis"})
      {:ok, _gout} = Mehungry.Health.create_condition(%{name: "Gout"})
      analyzed_paper(212_010, uc, "cohort")

      names = fn q -> Literature.conditions_for_search(q) |> Enum.map(& &1.condition.name) end

      # A condition with no digested research is still reachable from the search
      # (the old with-research catalog would never return it).
      assert names.("gou") == ["Gout"]
      # And the match is fuzzy (typo tolerant) on a research condition.
      assert names.("colitus") == ["Ulcerative Colitis"]
    end
  end

  # ── Full-text sections (enriched /analyze → StudyFullText) ───────────────────

  # A one-section, one-paragraph outline (the shape the enriched extractor adds to
  # each `paper_claims[]` entry). Offsets are absolute into the canonical text.
  defp sections_fixture do
    [
      %{
        "section_id" => "sec-a",
        "index" => 0,
        "title" => "Introduction",
        "start_char" => 0,
        "end_char" => 41,
        "paragraphs" => [
          %{
            "paragraph_id" => "par-a",
            "start_char" => 0,
            "end_char" => 41,
            "text" => "Fiber improves remission in colitis here."
          }
        ]
      }
    ]
  end

  defp response_with_sections(pmid, sections) do
    resp = response(pmid, [claim("c1", "improves", "positive")])
    [pc] = resp["paper_claims"]
    pc = Map.put(pc, "sections", sections)
    %{resp | "paper_claims" => [pc]}
  end

  describe "ResearchIngestion.target_pmids/2 selection" do
    alias Mehungry.Literature.ResearchIngestion

    defp analyzed_with_source(pmid, condition, source_type) do
      {:ok, study} = Literature.upsert_study(%{pmid: pmid, title: "P#{pmid}"})
      link_condition(study, condition)
      {:ok, _} = Literature.store_analysis_response(response(pmid, [claim("c1", "x", "positive")], source_type))
      study
    end

    test "normal run skips all already-analyzed papers; force retries unknown + open-access but not known-abstract" do
      {:ok, cond} = Mehungry.Health.create_condition(%{name: "Sel"})
      oa = analyzed_with_source(214_001, cond, "open_access")
      unknown = analyzed_with_source(214_002, cond, nil)
      abstract = analyzed_with_source(214_003, cond, "abstract")

      # Non-force: nothing new to do (all three already analyzed).
      assert ResearchIngestion.target_pmids(cond.id, false) == []

      # Force: re-includes the open-access + the nil/unknown paper (worth retrying
      # to backfill sections), but still skips the known-abstract one.
      forced = ResearchIngestion.target_pmids(cond.id, true) |> MapSet.new()
      assert MapSet.member?(forced, to_string(oa.pmid))
      assert MapSet.member?(forced, to_string(unknown.pmid))
      refute MapSet.member?(forced, to_string(abstract.pmid))
    end
  end

  describe "full-text sections" do
    test "stores a StudyFullText outline when the paper carries sections" do
      {:ok, study} = Literature.upsert_study(%{pmid: 311_001, title: "Fiber"})

      {:ok, _} =
        Literature.store_analysis_response(response_with_sections(311_001, sections_fixture()))

      ft = Literature.get_full_text(study.id)
      assert ft.source == "mehungry_extractor"
      assert [%{"section_id" => "sec-a", "title" => "Introduction"}] = ft.sections
      # body reconstructed from the paragraph slices.
      assert ft.body == "Fiber improves remission in colitis here."
    end

    test "a sections-less paper upserts no full text" do
      {:ok, study} = Literature.upsert_study(%{pmid: 311_002, title: "Fiber"})

      {:ok, _} =
        Literature.store_analysis_response(response(311_002, [claim("c1", "improves", "positive")]))

      refute Literature.get_full_text(study.id)
    end

    test "grouped_research_for_condition marks has_full_text + a section outline" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "UC-FT"})

      {:ok, with_ft} = Literature.upsert_study(%{pmid: 311_010, title: "P1"})
      link_condition(with_ft, uc)

      resp =
        311_010
        |> response_with_sections(sections_fixture())
        |> put_in(["papers", Access.at(0), "study_design"], "cohort")

      {:ok, _} = Literature.store_analysis_response(resp)

      {:ok, without_ft} = Literature.upsert_study(%{pmid: 311_011, title: "P2"})
      link_condition(without_ft, uc)
      no_sec = put_in(response(311_011, [claim("c1", "improves", "positive")]),
                 ["papers", Access.at(0), "study_design"], "cohort")
      {:ok, _} = Literature.store_analysis_response(no_sec)

      [group] = Literature.grouped_research_for_condition(uc.id)
      by_study = Map.new(group.analyses, &{&1.study_id, &1})

      assert by_study[with_ft.id].has_full_text
      assert [%{"id" => "sec-a", "title" => "Introduction"}] = by_study[with_ft.id].outline
      refute by_study[without_ft.id].has_full_text
      assert by_study[without_ft.id].outline == []
    end

    test "full_text_for_reader returns sections + paragraph-relative claim spans" do
      {:ok, study} = Literature.upsert_study(%{pmid: 311_020, title: "Fiber"})

      claim =
        Map.put(claim("c1", "improves", "positive"), "evidence", [
          %{
            "paragraph_id" => "par-a",
            "start_char" => 0,
            "end_char" => 5,
            "quoted_text" => "Fiber"
          }
        ])

      resp = response(311_020, [claim])
      [pc] = resp["paper_claims"]
      pc = Map.put(pc, "sections", sections_fixture())
      {:ok, _} = Literature.store_analysis_response(%{resp | "paper_claims" => [pc]})

      data = Literature.full_text_for_reader(study.id)
      assert [%{"section_id" => "sec-a"}] = data.sections
      # Absolute evidence offsets (0..5) made paragraph-relative (paragraph starts at 0).
      assert [%{start: 0, end: 5, polarity: "positive"}] = data.spans_by_paragraph["par-a"]
    end

    test "full_text_for_reader is nil without a stored outline" do
      {:ok, study} = Literature.upsert_study(%{pmid: 311_030, title: "Fiber"})
      {:ok, _} = Literature.store_analysis_response(response(311_030, [claim("c1", "improves", "positive")]))
      refute Literature.full_text_for_reader(study.id)
    end
  end

  describe "grouped_research_for_condition/1" do
    test "groups into evidence-hierarchy buckets (strongest first), hides empties, drops errors" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "UC"})
      analyzed_paper(212_001, uc, "cohort")
      analyzed_paper(212_002, uc, "systematic_review")
      analyzed_paper(212_003, uc, "randomized_controlled_trial")

      # An error-status paper is stored but must not surface in the grouping.
      {:ok, estudy} = Literature.upsert_study(%{pmid: 212_099, title: "err"})
      link_condition(estudy, uc)

      {:ok, _} =
        Literature.store_analysis_response(%{
          "run" => %{},
          "papers" => [
            %{"pmid" => "212099", "status" => "error", "error" => "boom", "study_design" => "cohort"}
          ],
          "paper_claims" => [],
          "warnings" => []
        })

      groups = Literature.grouped_research_for_condition(uc.id)

      assert Enum.map(groups, & &1.key) == [:systematic_review, :controlled_trial, :cohort]
      assert Enum.all?(groups, &match?([_ | _], &1.analyses))
      # The error paper did not join the cohort bucket.
      cohort = Enum.find(groups, &(&1.key == :cohort))
      assert length(cohort.analyses) == 1
    end

    test "within a bucket, most-recent then largest-sample first" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "UC2"})
      analyzed_paper(212_010, uc, "cohort", year: 2019, n: 100)
      analyzed_paper(212_011, uc, "cohort", year: 2023, n: 50)
      analyzed_paper(212_012, uc, "cohort", year: 2023, n: 400)

      [group] = Literature.grouped_research_for_condition(uc.id)
      assert Enum.map(group.analyses, &{&1.publication_year, &1.sample_size}) ==
               [{2023, 400}, {2023, 50}, {2019, 100}]
    end

    test "within a bucket, MEDLINE-indexed papers rank before non-indexed (same recency)" do
      {:ok, uc} = Mehungry.Health.create_condition(%{name: "UC3"})
      analyzed_paper(212_020, uc, "cohort", year: 2023, n: 100, status: "PubMed-not-MEDLINE")
      analyzed_paper(212_021, uc, "cohort", year: 2023, n: 100, status: "MEDLINE")

      [group] = Literature.grouped_research_for_condition(uc.id)
      assert Enum.map(group.analyses, & &1.study.citation_status) ==
               ["MEDLINE", "PubMed-not-MEDLINE"]
    end
  end
end
