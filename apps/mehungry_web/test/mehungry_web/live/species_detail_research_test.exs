defmodule MehungryWeb.SpeciesDetailResearchTest do
  @moduledoc """
  The "Research findings" section on the species detail page. A well-studied
  species can carry thousands of mined facts, so the page renders only the curated
  on-subject verified top set (the crawlable SEO payload) while the honest verdict
  tally still reports the true totals; the rest is reached via the search box.
  """
  use MehungryWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Mehungry.Food
  alias Mehungry.FactMining.SpeciesMinedFact
  alias Mehungry.Repo

  defp species_fixture do
    {:ok, species} =
      Food.FoundementalFoods.create_species(%{
        name: "Researchuniq#{System.unique_integer([:positive])}",
        scientific_name: "Testus researchus"
      })

    species
  end

  defp insert_fact(species, attrs) do
    %SpeciesMinedFact{}
    |> SpeciesMinedFact.changeset(
      Map.merge(%{foundemental_species_id: species.id, label: "verified"}, attrs)
    )
    |> Repo.insert!()
  end

  test "dead render caps verified facts at 10 but the tally reports the true total",
       %{conn: conn} do
    sp = species_fixture()

    # 15 verified facts, lexical fact_ids so the fact_id tiebreak is deterministic.
    for i <- 1..15 do
      n = String.pad_leading(Integer.to_string(i), 2, "0")

      insert_fact(sp, %{
        fact_id: "f#{n}",
        text: "Finding #{n} about the food",
        lay_tier: "lead",
        lay_clarity: 1.0
      })
    end

    html = conn |> get(~p"/foods/#{String.downcase(sp.name)}") |> html_response(200)

    # True total surfaces in the tally (not the capped 10).
    assert html =~ "15"
    assert html =~ "corroborated"
    # Only the top 10 render; the 11th–15th are omitted from the dead render.
    assert html =~ "Finding 01 about the food"
    assert html =~ "Finding 10 about the food"
    refute html =~ "Finding 11 about the food"
    refute html =~ "Finding 15 about the food"
    # The search affordance is present for exploring the rest.
    assert html =~ "search_research"
  end

  test "off-subject (hide) and non-verified facts are excluded from the curated set",
       %{conn: conn} do
    sp = species_fixture()
    insert_fact(sp, %{fact_id: "v", text: "On subject verified claim", lay_tier: "lead"})
    insert_fact(sp, %{fact_id: "h", text: "Off subject background claim", lay_tier: "hide"})

    insert_fact(sp, %{
      fact_id: "c",
      text: "Contradicted disputed claim",
      label: "contradicted",
      conflicting_pmid: "9"
    })

    html = conn |> get(~p"/foods/#{String.downcase(sp.name)}") |> html_response(200)

    assert html =~ "On subject verified claim"
    refute html =~ "Off subject background claim"
    refute html =~ "Contradicted disputed claim"
  end

  test "diet-relevant findings lead; mechanistic ones are demoted into a collapsed section",
       %{conn: conn} do
    sp = species_fixture()

    insert_fact(sp, %{
      fact_id: "h",
      text: "Human cohort dietary finding",
      lay_tier: "show",
      study_design: "cohort"
    })

    # Strongest lay signal, but a mechanistic design — it must still be demoted.
    insert_fact(sp, %{
      fact_id: "m",
      text: "Molecular docking lab finding",
      lay_tier: "lead",
      lay_clarity: 1.0,
      study_design: "mechanistic_experiment"
    })

    {:ok, view, _html} = live(conn, ~p"/foods/#{String.downcase(sp.name)}")
    html = render_async(view)

    # Both render, but the mechanistic one sits under the collapsed disclosure.
    assert html =~ "Human cohort dietary finding"
    assert html =~ "Molecular docking lab finding"
    assert html =~ "mechanism studies"
    # Recipes anchor target is present; no chip/link since this species has no recipes.
    assert html =~ ~s(id="recipes")
    refute html =~ ~s(href="#recipes")
  end

  test "an all-mechanistic species shows the preclinical note instead of an empty section",
       %{conn: conn} do
    sp = species_fixture()

    insert_fact(sp, %{
      fact_id: "m1",
      text: "In vitro assay result",
      lay_tier: "lead",
      study_design: "in_vitro"
    })

    html = conn |> get(~p"/foods/#{String.downcase(sp.name)}") |> html_response(200)

    assert html =~ "In vitro assay result"
    assert html =~ "preclinical or lab studies"
  end

  test "search surfaces contradicted + off-subject facts the curated set omits",
       %{conn: conn} do
    sp = species_fixture()
    insert_fact(sp, %{fact_id: "v", text: "Cranberry corroborated benefit", lay_tier: "lead"})

    insert_fact(sp, %{
      fact_id: "c",
      text: "Cranberry contradicted on cholesterol",
      label: "contradicted",
      conflicting_pmid: "9"
    })

    {:ok, view, _html} = live(conn, ~p"/foods/#{String.downcase(sp.name)}")
    html = render_async(view)

    # Curated view: contradicted fact hidden until searched.
    assert html =~ "Cranberry corroborated benefit"
    refute html =~ "Cranberry contradicted on cholesterol"

    searched =
      view
      |> form("form[phx-change=search_research]", %{"q" => "contradicted"})
      |> render_change()

    assert searched =~ "Cranberry contradicted on cholesterol"
  end
end
