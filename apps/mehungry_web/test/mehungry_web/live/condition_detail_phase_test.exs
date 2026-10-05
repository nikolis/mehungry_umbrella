defmodule MehungryWeb.ConditionDetailPhaseTest do
  # Verifies the phase selector + phase-specific guidance + "Research on this condition"
  # sections on the public condition page.
  use MehungryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Mehungry.AccountsFixtures

  alias Mehungry.{Food, Health, Literature, MealBlueprints}
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

  test "phase-less dietary recommendations show under the General tab, not per-phase", %{conn: conn} do
    %{condition: condition} = setup_uc()
    {:ok, compound} = Food.upsert_compound(%{name: "Resistant Starch", compound_type: "other"})

    {:ok, _} =
      Health.add_recommendation(condition.id, compound.id, %{
        recommendation: "encourage",
        source: "guideline",
        source_reference: %{"label" => "g", "url" => "https://example.org"}
      })

    {:ok, view, html} = live(conn, "/en/conditions/#{condition.id}")

    # Default phase is Active Flare, so the phase-less dietary rec is not shown yet.
    assert html =~ "Advice by disease phase"
    refute html =~ "Resistant Starch"

    # Under the General tab it appears, inside the phase panel.
    general = render_click(view, "select_state", %{"state" => "general"})
    assert general =~ "Dietary Recommendations"
    assert general =~ "Resistant Starch"

    # Selecting a specific phase hides the phase-less dietary rec again.
    refute render_click(view, "select_state", %{"state" => "active_flare"}) =~ "Resistant Starch"
  end

  test "a condition with no states renders no phase selector", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Kidney Stones"})

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    refute html =~ "Advice by disease phase"
  end

  test "a stateless condition surfaces general free-text notes in their own block", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Mystery Ailment"})

    # A verified unmatched suggestion lands as a general (nil-state) free-text note.
    {:ok, _} =
      Health.upsert_state_recommendation(%{
        condition_id: condition.id,
        condition_state_id: nil,
        raw_food_term: "bone broth",
        recommendation: "encourage",
        source: "literature"
      })

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    # No phase layer, but the note shows in the dedicated text-only section.
    refute html =~ "Advice by disease phase"
    assert html =~ "Noted dietary suggestions"
    assert html =~ "bone broth"
  end

  test "a directly-matched species renders as a food card", %{conn: conn} do
    {:ok, condition} = Health.create_condition(%{name: "Anemia"})
    {:ok, species} = Food.create_foundemental_species(%{name: "Spinach"})

    {:ok, _} =
      Health.upsert_state_recommendation(%{
        condition_id: condition.id,
        condition_state_id: nil,
        species_id: species.id,
        recommendation: "encourage",
        source: "literature"
      })

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    # Shown as a food card under "Foods to Eat" — not as a phase row or free-text note.
    assert html =~ "Foods to Eat"
    assert html =~ "Spinach"
    refute html =~ "Noted dietary suggestions"
  end

  test "a directly-matched public blueprint renders a Suggested Meal Plans card", %{conn: conn} do
    user = user_fixture()
    {:ok, condition} = Health.create_condition(%{name: "Heart Health"})

    {:ok, blueprint} =
      user.id
      |> MealBlueprints.default_blueprint_attrs("Mediterranean Week")
      |> Map.put(:visibility, "public")
      |> MealBlueprints.create_blueprint()

    {:ok, _} =
      Health.upsert_state_recommendation(%{
        condition_id: condition.id,
        condition_state_id: nil,
        blueprint_id: blueprint.id,
        recommendation: "encourage",
        source: "literature"
      })

    html = conn |> get("/en/conditions/#{condition.id}") |> html_response(200)

    assert html =~ "Suggested Meal Plans"
    assert html =~ "Mediterranean Week"
    assert html =~ "/blueprints/#{blueprint.slug}"
  end
end
