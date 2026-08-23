defmodule MehungryWeb.Api.LocalAiTest do
  use MehungryWeb.ConnCase, async: false

  import Mehungry.FoodFixtures

  alias Mehungry.{Food, Literature, Repo}
  alias Mehungry.Food.CompoundMeasurementCandidate
  alias Mehungry.Food.GlycemicIndexCandidate

  defp token, do: Application.get_env(:mehungry, :local_ai_api_token)

  setup do
    spinach = ingredient_fixture(%{name: "spinach"})
    {:ok, vitc} = Food.upsert_compound(%{name: "L-Ascorbic Acid", compound_type: "other"})

    {:ok, species} =
      Food.create_foundemental_species(%{
        "name" => "Spinach",
        "scientific_name" => "Spinacia oleracea"
      })

    {:ok, _} = Food.assign_foundemental_ingredient(species.id, spinach.id, "spinach")

    {:ok, study} =
      Literature.upsert_study(%{
        pmid: 12_345,
        title: "Vitamin C in spinach",
        retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })

    {:ok, _} =
      Literature.link_study_ingredient(%{
        study_id: study.id,
        ingredient_id: spinach.id,
        search_term: "Spinacia oleracea ascorbic"
      })

    {:ok, _} =
      Literature.upsert_entity_mention(%{
        study_id: study.id,
        entity_type: "chemical",
        normalized_identifier: "mesh:D001205",
        text_span: "ascorbic acid",
        offset: 1,
        compound_id: vitc.id
      })

    %{spinach: spinach, vitc: vitc, species: species, study: study}
  end

  defp auth(conn), do: put_req_header(conn, "authorization", "Bearer " <> token())

  describe "authentication" do
    test "rejects a request with no token", %{conn: conn} do
      conn = get(conn, ~p"/api/local_ai/pending")
      assert json_response(conn, 401)
    end

    test "rejects a request with a wrong token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer nope")
        |> get(~p"/api/local_ai/pending")

      assert json_response(conn, 401)
    end
  end

  describe "GET /pending" do
    test "returns unfetched studies with their compounds", %{conn: conn, study: study, vitc: vitc} do
      conn = conn |> auth() |> get(~p"/api/local_ai/pending?limit=10")
      body = json_response(conn, 200)

      assert [payload] = body["studies"]
      assert payload["study_id"] == study.id
      assert payload["pmid"] == 12_345
      assert [%{"id" => cid, "name" => "L-Ascorbic Acid"}] = payload["compounds"]
      assert cid == vitc.id
    end

    test "flags extract_gi only for studies found by the GI crawl term", %{
      conn: conn,
      spinach: spinach,
      study: vitc_study
    } do
      {:ok, gi_study} =
        Literature.upsert_study(%{
          pmid: 99_001,
          title: "GI of spinach",
          retrieved_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })

      {:ok, _} =
        Literature.link_study_ingredient(%{
          study_id: gi_study.id,
          ingredient_id: spinach.id,
          search_term: "Spinacia oleracea glycemic index"
        })

      body = conn |> auth() |> get(~p"/api/local_ai/pending?limit=10") |> json_response(200)
      flags = Map.new(body["studies"], &{&1["study_id"], &1["extract_gi"]})

      assert flags[gi_study.id] == true
      # the vitamin-C study (found by the "ascorbic" term) is not GI-discovered
      assert flags[vitc_study.id] == false
    end
  end

  describe "POST /gi_candidates" do
    test "fans a GI finding across the study's species as pending candidates", ctx do
      %{conn: conn, study: study, species: species} = ctx

      conn =
        conn
        |> auth()
        |> post(~p"/api/local_ai/gi_candidates", %{
          "candidates" => [
            %{
              "study_id" => study.id,
              "gi_value" => 54.0,
              "gi_sem" => 3.0,
              "iso_method" => true,
              "reference_food" => "glucose",
              "sample_size" => 10,
              "score" => 0.4,
              "extraction_method" => "automated"
            }
          ]
        })

      assert json_response(conn, 200)["written"] == 1

      assert [cand] = Repo.all(GlycemicIndexCandidate)
      assert cand.foundemental_species_id == species.id
      assert cand.study_id == study.id
      assert cand.gi_value == 54.0
      assert cand.gi_sem == 3.0
      assert cand.iso_method
      assert cand.status == "pending"
      assert cand.enrichment_source_id
    end
  end

  describe "POST /full_text" do
    test "stores body + ledgers the attempt so the study leaves pending", %{
      conn: conn,
      study: study
    } do
      conn =
        conn
        |> auth()
        |> post(~p"/api/local_ai/full_text", %{
          "study_id" => study.id,
          "pmcid" => "PMC42",
          "source" => "pmc_oa",
          "body" => "Results: ascorbic acid 260 mg/100 g by HPLC.",
          "outcome" => "open_access"
        })

      assert json_response(conn, 200)["ok"] == true
      assert Literature.get_full_text(study.id).pmcid == "PMC42"
      assert Literature.pmc_attempted?(study.id)

      # Now excluded from the pending set.
      pending =
        build_conn() |> auth() |> get(~p"/api/local_ai/pending?limit=10") |> json_response(200)

      assert pending["studies"] == []
    end

    test "ledgers a skip outcome with no body", %{conn: conn, study: study} do
      conn =
        conn
        |> auth()
        |> post(~p"/api/local_ai/full_text", %{"study_id" => study.id, "outcome" => "no_pmcid"})

      assert json_response(conn, 200)
      assert Literature.get_full_text(study.id) == nil
      assert Literature.pmc_attempted?(study.id)
    end
  end

  describe "POST /candidates" do
    test "fans a finding out across the study's species and upserts candidates", ctx do
      %{conn: conn, study: study, vitc: vitc, species: species} = ctx

      conn =
        conn
        |> auth()
        |> post(~p"/api/local_ai/candidates", %{
          "candidates" => [
            %{
              "study_id" => study.id,
              "compound_id" => vitc.id,
              "value" => 260.0,
              "unit" => "mg/100 g",
              "analytical_method" => "HPLC",
              "score" => 0.4,
              "extraction_method" => "automated"
            }
          ]
        })

      assert json_response(conn, 200)["written"] == 1

      assert [cand] = Repo.all(CompoundMeasurementCandidate)
      assert cand.foundemental_species_id == species.id
      assert cand.compound_id == vitc.id
      assert cand.value == 260.0
      assert cand.unit == "mg/100 g"
      assert cand.status == "pending"
    end
  end
end
