defmodule MehungryWeb.Api.LocalAiConditionRecTest do
  use MehungryWeb.ConnCase, async: false

  alias Mehungry.{Health, Literature}
  alias Mehungry.Health.ConditionRecCandidates

  defp token, do: Application.get_env(:mehungry, :local_ai_api_token)
  defp auth(conn), do: put_req_header(conn, "authorization", "Bearer " <> token())

  setup do
    {:ok, condition} = Health.create_condition(%{name: "Ulcerative Colitis"})

    {:ok, flare} =
      Health.upsert_state(%{
        condition_id: condition.id,
        name: "Active Flare",
        slug: "active_flare",
        is_default: true
      })

    {:ok, study} = Literature.upsert_study(%{pmid: 900_123, title: "UC diet"})

    {:ok, _} =
      Literature.link_study_condition(%{
        study_id: study.id,
        condition_id: condition.id,
        search_term: "Ulcerative Colitis diet"
      })

    %{condition: condition, flare: flare, study: study}
  end

  test "rejects requests without a valid token", %{conn: conn} do
    assert json_response(get(conn, ~p"/api/local_ai/condition_pending"), 401)
  end

  test "GET /condition_pending returns the pair with its states", ctx do
    %{conn: conn, condition: condition, study: study} = ctx
    resp = conn |> auth() |> get(~p"/api/local_ai/condition_pending") |> json_response(200)

    assert [pair] = resp["pairs"]
    assert pair["study_id"] == study.id
    assert pair["pmid"] == study.pmid
    assert pair["condition"]["name"] == condition.name
    assert Enum.map(pair["states"], & &1["slug"]) == ["active_flare"]
  end

  test "POST candidates writes a review-gated candidate, ledgers the pair, is idempotent", ctx do
    %{conn: conn, condition: condition, flare: flare, study: study} = ctx

    body = %{
      "study_id" => study.id,
      "condition_id" => condition.id,
      "findings" => [
        %{
          "raw_term" => "insoluble fiber",
          "target_kind" => "nutrient",
          "direction" => "avoid",
          "condition_state_slug" => "active_flare",
          "severity" => "high",
          "confidence" => 0.8
        }
      ]
    }

    resp =
      conn
      |> auth()
      |> post(~p"/api/local_ai/condition_recommendation_candidates", body)
      |> json_response(200)

    assert resp["written"] == 1

    assert [cand] = ConditionRecCandidates.list_pending_candidates()
    assert cand.condition_state_id == flare.id
    assert cand.nutrient_name == "Fiber"
    assert cand.suggested_recommendation == "avoid"

    # the pair has left the pending set (attempt ledgered)
    assert ConditionRecCandidates.list_pending_extraction(10) == []

    # re-posting the same finding is idempotent (dedup_key)
    conn2 =
      build_conn()
      |> auth()
      |> post(~p"/api/local_ai/condition_recommendation_candidates", body)

    assert json_response(conn2, 200)["written"] == 1
    assert length(ConditionRecCandidates.list_pending_candidates()) == 1
  end

  test "POST with zero findings still ledgers the attempt (termination)", ctx do
    %{conn: conn, condition: condition, study: study} = ctx

    resp =
      conn
      |> auth()
      |> post(~p"/api/local_ai/condition_recommendation_candidates", %{
        "study_id" => study.id,
        "condition_id" => condition.id,
        "findings" => []
      })
      |> json_response(200)

    assert resp["written"] == 0
    assert ConditionRecCandidates.list_pending_extraction(10) == []
  end

  test "POST missing required fields is a 422", %{conn: conn} do
    assert conn
           |> auth()
           |> post(~p"/api/local_ai/condition_recommendation_candidates", %{"findings" => []})
           |> json_response(422)
  end
end
