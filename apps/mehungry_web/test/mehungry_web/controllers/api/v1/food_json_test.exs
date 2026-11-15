defmodule MehungryWeb.Api.V1.FoodJSONTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.FoundementalFoodSpecies
  alias Mehungry.FactMining.SpeciesMinedFact
  alias MehungryWeb.Api.V1.FoodJSON

  test "species_summary/1 includes a derived icon" do
    summary = FoodJSON.species_summary(%FoundementalFoodSpecies{id: 1, name: "Apple"})
    assert summary.icon == "🍎"
    assert summary.slug == "apple"
  end

  test "species_summary/1 honors a curator's icon override" do
    summary = FoodJSON.species_summary(%FoundementalFoodSpecies{id: 1, name: "Apple", icon: "🦄"})
    assert summary.icon == "🦄"
  end

  test "species_detail/3 carries the icon through the merged summary" do
    detail = FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, [], [])
    assert detail.data.icon == "🥬"
  end

  test "species_detail serializes a mined fact's lay presentation hint" do
    fact = %SpeciesMinedFact{
      text: "Spinach is high in iron.",
      label: "verified",
      pmid: "123",
      lay_tier: "lead",
      lay_clarity: 0.8,
      lay_flags: ["undefined_acronym:GSE"]
    }

    detail = FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, [fact], [])
    [research] = detail.data.research

    assert research.lay == %{tier: "lead", clarity: 0.8, flags: ["undefined_acronym:GSE"]}
  end

  test "species_detail defaults lay flags to [] when absent" do
    fact = %SpeciesMinedFact{text: "x", label: "verified", pmid: "1"}
    detail = FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, [fact], [])
    [research] = detail.data.research

    assert research.lay == %{tier: nil, clarity: nil, flags: []}
  end
end
