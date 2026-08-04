defmodule MehungryWeb.ProfessionalLive.HealthConditionsTest do
  use MehungryWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Health, Literature}
  alias Mehungry.Health.RecommendationCandidates

  @admin_email Application.compile_env(:mehungry, :admin_email)

  setup %{conn: conn} do
    conn = log_in_user(conn, user_fixture(%{email: @admin_email}))
    {:ok, oxalate} = Food.upsert_compound(%{name: "Oxalate", compound_type: "oxalate"})
    %{conn: conn, oxalate: oxalate}
  end

  test "creates a condition, attaches a recommendation, and removes it", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    # Create a condition.
    view
    |> form("form[phx-submit=save_condition]",
      condition: %{name: "Kidney Stones", category: "renal"}
    )
    |> render_submit()

    assert render(view) =~ "Kidney Stones"
    condition = Health.get_condition_by_name("Kidney Stones")
    assert condition

    # Attach a compound recommendation.
    view
    |> form("form[phx-submit=save_recommendation]",
      recommendation: %{
        condition_id: condition.id,
        compound_id: oxalate.id,
        recommendation: "avoid",
        severity: "high",
        source: "guideline"
      }
    )
    |> render_submit()

    assert [rec] = Health.recommendations_for_condition(condition.id)
    assert rec.compound_id == oxalate.id
    assert rec.recommendation == "avoid"
    assert render(view) =~ "Oxalate"

    # Remove the recommendation.
    view
    |> element("button[phx-click=delete_recommendation][phx-value-id='#{rec.id}']")
    |> render_click()

    assert Health.recommendations_for_condition(condition.id) == []
  end

  test "deletes a condition and its recommendations", %{conn: conn, oxalate: oxalate} do
    {:ok, _} =
      Health.add_recommendation(%{name: "Gout", category: "metabolic"}, oxalate.id, %{
        recommendation: "limit",
        source: "guideline"
      })

    gout = Health.get_condition_by_name("Gout")
    {:ok, view, _html} = live(conn, ~p"/professional/health")

    view
    |> element("button[phx-click=delete_condition][phx-value-id='#{gout.id}']")
    |> render_click()

    assert Health.get_condition(gout.id) == nil
    assert Health.recommendations_for_condition(gout.id) == []
  end

  test "reviews a literature-derived candidate and promotes it into a recommendation", %{
    conn: conn,
    oxalate: oxalate
  } do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})
    {:ok, study} = Literature.upsert_study(%{pmid: 770_001, title: "s"})

    {:ok, _} =
      Literature.upsert_entity_relation(%{
        study_id: study.id,
        type: "Positive_Correlation",
        score: 0.98,
        entity1_type: "chemical",
        entity1_identifier: "mesh:D010070",
        entity2_type: "disease",
        entity2_identifier: "mesh:D007669",
        compound_id: oxalate.id,
        condition_id: condition.id
      })

    {:ok, %{candidate: candidate}} =
      RecommendationCandidates.derive_candidate(condition.id, oxalate.id)

    {:ok, view, _html} = live(conn, ~p"/professional/health")
    assert render(view) =~ "Review derived recommendations"
    assert render(view) =~ "suggests avoid"

    view
    |> form("form[phx-submit=promote_recommendation]",
      id: candidate.id,
      recommendation: "avoid",
      severity: "high"
    )
    |> render_submit()

    assert [rec] = Health.recommendations_for_condition(condition.id)
    assert rec.recommendation == "avoid"
    assert rec.source == "literature"
    assert rec.compound_id == oxalate.id
    # Promoted candidate leaves the review queue.
    assert RecommendationCandidates.list_pending_candidates() == []
  end

  test "non-admin is redirected away" do
    conn = log_in_user(build_conn(), user_fixture(%{email: "notadmin@example.com"}))
    assert {:error, {:redirect, %{to: "/home"}}} = live(conn, ~p"/professional/health")
  end
end
