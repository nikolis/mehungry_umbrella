defmodule MehungryWeb.SpeciesDetailPhotoTest do
  @moduledoc """
  The licence-gated Wikimedia Commons lead photo on the species detail page — it
  replaces the emoji icon and always carries an attribution credit (tested on the
  crawlable dead render).
  """
  use MehungryWeb.ConnCase, async: true

  alias Mehungry.Food

  defp species_fixture(name, attrs) do
    {:ok, species} = Food.FoundementalFoods.create_species(Map.merge(%{name: name}, attrs))
    species
  end

  test "renders the photo + author · licence · Commons credit when present", %{conn: conn} do
    name = "Photosp#{System.unique_integer([:positive])}"

    species_fixture(name, %{
      image_url: "https://stub/species_images/x.jpg",
      image_license: "CC BY-SA 3.0",
      image_license_url: "https://creativecommons.org/licenses/by-sa/3.0",
      image_attribution: "Alvesgaspar",
      image_source_url: "https://commons.wikimedia.org/wiki/File:Fennel.jpg"
    })

    html = conn |> get(~p"/foods/#{String.downcase(name)}") |> html_response(200)

    assert html =~ "https://stub/species_images/x.jpg"
    assert html =~ "Alvesgaspar"
    assert html =~ "CC BY-SA 3.0"
    assert html =~ "https://creativecommons.org/licenses/by-sa/3.0"
    assert html =~ "https://commons.wikimedia.org/wiki/File:Fennel.jpg"
    assert html =~ "Wikimedia Commons"
  end

  test "falls back to the emoji icon with no credit when there is no photo", %{conn: conn} do
    name = "Emojisp#{System.unique_integer([:positive])}"
    species_fixture(name, %{})

    html = conn |> get(~p"/foods/#{String.downcase(name)}") |> html_response(200)

    refute html =~ "species_images/"
    refute html =~ "Wikimedia Commons"
  end
end
