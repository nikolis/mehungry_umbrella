defmodule MehungryWeb.ConditionDetailPhaseTest do
  # Verifies the phase selector + phase-specific guidance + "Research on this condition"
  # sections on the public condition page.
  use MehungryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mehungry.{Health, Literature}
  alias Mehungry.Health.ConditionRecCandidates

  defp setup_uc do
    {:ok, condition} = Health.create_condition(%{name: "Ulcerative Colitis"})

    {:ok, flare} =
      Health.upsert_state(%{condition_id: condition.id, name: "Active Flare", slug: "active_flare", is_default: true})

    {:ok, _remission} =
      Health.upsert_state(%{condition_id: condition.id, name: "Remission", slug: "remission", position: 1})

    {:ok, study} = Literature.upsert_study(%{pmid: 910_222, title: "UC dietary management trial"})
    {:ok, _} = Literature.link_study_condition(%{study_id: study.id, condition_id: condition.id, search_term: "Ulcerative Colitis diet"})

    {:ok, cand} =
      ConditionRecCandidates.upsert_candidate(%{
        "study_id" => study.id,
        "condition_id" => condition.id,
        "raw_term" => "low-residue",
        "target_kind" => "food_pattern",
        "direction" => "encourage",
        "condition_state_slug" => "active_flare"
      })

    {:ok, _rec} = ConditionRecCandidates.promote_candidate(cand.id, %{"recommendation" => "encourage"})

    %{condition: condition, flare: flare, study: study}
  end

  test "renders the phase selector, default-phase guidance, and research section", %{conn: conn} do
    %{condition: condition} = setup_uc()

    {:ok, view, html} = live(conn, "/en/conditions/#{condition.id}")

    # phase selector + both states present
    assert html =~ "Advice by disease phase"
    assert html =~ "Active Flare"
    assert html =~ "Remission"

    # default phase (Active Flare) shows its promoted guidance
    assert html =~ "low-residue"

    # research section lists the crawled study
    assert html =~ "Research on this condition"
    assert html =~ "UC dietary management trial"

    # switching to Remission hides the flare-only guidance
    refute render_click(view, "select_state", %{"state" => "remission"}) =~ "low-residue"

    # switching back to Active Flare shows it again
    assert render_click(view, "select_state", %{"state" => "active_flare"}) =~ "low-residue"
  end

  test "a condition with no states renders no phase selector", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    refute html =~ "Advice by disease phase"
  end
end
