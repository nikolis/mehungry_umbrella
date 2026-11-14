defmodule Mehungry.Science.PipelineResetTest do
  use Mehungry.DataCase, async: false

  alias Mehungry.Science.PipelineReset
  alias Mehungry.Literature
  alias Mehungry.Literature.{StudyAnalysis, StudyFullText}

  describe "reset_extractor_data/0" do
    test "wipes extractor data, source-scopes full texts, and reports per-table counts" do
      {:ok, study} = Literature.upsert_study(%{pmid: 990_111, title: "Legacy"})
      {:ok, other} = Literature.upsert_study(%{pmid: 990_222, title: "Measurement"})

      {:ok, _} =
        %StudyAnalysis{}
        |> StudyAnalysis.changeset(%{study_id: study.id, status: "included", content_hash: "h"})
        |> Repo.insert()

      {:ok, extractor_ft} =
        %StudyFullText{}
        |> StudyFullText.changeset(%{study_id: study.id, source: "mehungry_extractor", body: "x"})
        |> Repo.insert()

      # A full text from the (separate) measurement-extraction pipeline must survive.
      {:ok, pmc_ft} =
        %StudyFullText{}
        |> StudyFullText.changeset(%{study_id: other.id, source: "pmc", body: "y"})
        |> Repo.insert()

      {:ok, _} = Mehungry.Extractor.update_settings(%{"base_url" => "http://ex:8000"})
      _run = Literature.ResearchIngestionRuns.start_run(1)

      counts = PipelineReset.reset_extractor_data()

      assert counts["study_analyses"] == 1
      assert counts["study_full_texts"] == 1
      assert counts["extractor_settings"] == 1
      assert counts["research_ingestion_runs"] == 1

      assert Repo.get(StudyFullText, extractor_ft.id) == nil
      assert Repo.get(StudyFullText, pmc_ft.id)
      assert Literature.get_analysis_by_study_id(study.id) == nil
      assert Mehungry.Extractor.get_settings() == nil
      assert Literature.ResearchIngestionRuns.latest_run() == nil
    end
  end
end
