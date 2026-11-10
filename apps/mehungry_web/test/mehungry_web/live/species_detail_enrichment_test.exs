defmodule MehungryWeb.SpeciesDetailEnrichmentTest do
  @moduledoc """
  The "Origins & cultivation" enrichment section on the species detail page. Tests the
  **dead render** (plain GET) specifically — that's the crawlable path the facts exist
  to feed, and where they must appear synchronously.
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Food

  defp species_fixture(name) do
    {:ok, species} =
      Food.FoundementalFoods.create_species(%{name: name, scientific_name: "Testus #{name}"})

    species
  end

  test "renders promoted origin + producers with the FAOSTAT credit", %{conn: conn} do
    name = "Enrichuniq#{System.unique_integer([:positive])}"
    sp = species_fixture(name)

    Food.record_species_wikidata_facts(sp.id, %{qid: "Q1", origin_region: "Central Asia"})
    Food.record_species_faostat_facts(sp.id, [%{country: "China", tonnes: 1.0, year: 2022}])
    Enum.each(Food.list_pending_species_facts(), &Food.promote_species_fact(&1.id))

    html = conn |> get(~p"/foods/#{String.downcase(name)}") |> html_response(200)

    assert html =~ "Origins &amp; cultivation" or html =~ "Origins & cultivation"
    assert html =~ "Central Asia"
    assert html =~ "China"
    assert html =~ "FAOSTAT"
    assert html =~ "CC BY 4.0"
  end

  test "omits the section entirely when no facts are promoted", %{conn: conn} do
    name = "Baresp#{System.unique_integer([:positive])}"
    sp = species_fixture(name)
    # pending (un-promoted) facts must not surface
    Food.record_species_wikidata_facts(sp.id, %{qid: "Q2", origin_region: "Nowhere"})

    html = conn |> get(~p"/foods/#{String.downcase(name)}") |> html_response(200)

    refute html =~ "Origins &amp; cultivation"
    refute html =~ "Nowhere"
  end
end
