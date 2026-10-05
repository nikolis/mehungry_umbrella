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
end
