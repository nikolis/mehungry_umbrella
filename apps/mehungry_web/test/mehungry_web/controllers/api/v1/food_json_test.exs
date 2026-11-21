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

  test "species_summary/1 image is nil without a stored photo" do
    summary = FoodJSON.species_summary(%FoundementalFoodSpecies{id: 1, name: "Apple"})
    assert summary.image == nil
  end

  test "species_summary/1 exposes the photo + attribution when present" do
    summary =
      FoodJSON.species_summary(%FoundementalFoodSpecies{
        id: 1,
        name: "Fennel",
        image_url: "https://stub/species_images/1.jpg",
        image_license: "CC BY-SA 3.0",
        image_license_url: "https://creativecommons.org/licenses/by-sa/3.0",
        image_attribution: "Alvesgaspar",
        image_source_url: "https://commons.wikimedia.org/wiki/File:Fennel.jpg"
      })

    assert summary.image == %{
             url: "https://stub/species_images/1.jpg",
             license: "CC BY-SA 3.0",
             license_url: "https://creativecommons.org/licenses/by-sa/3.0",
             attribution: "Alvesgaspar",
             source_url: "https://commons.wikimedia.org/wiki/File:Fennel.jpg"
           }
  end

  test "species_detail/3 carries the icon through the merged summary" do
    detail = FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, %{}, [])
    assert detail.data.icon == "🥬"
  end

  test "species_detail serializes a mined fact's lay presentation hint + reason" do
    fact = %SpeciesMinedFact{
      text: "Spinach is high in iron.",
      label: "verified",
      pmid: "123",
      reason: "Backed by two independent trials.",
      lay_tier: "lead",
      lay_clarity: 0.8,
      lay_flags: ["undefined_acronym:GSE"]
    }

    research = %{relevant: [fact], mechanistic: [], mechanistic_count: 0}

    detail =
      FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, research, [])

    [serialized] = detail.data.research.relevant

    assert serialized.lay == %{tier: "lead", clarity: 0.8, flags: ["undefined_acronym:GSE"]}
    assert serialized.reason == "Backed by two independent trials."
  end

  test "research_fact/1 defaults lay flags to [] and a blank reason to nil" do
    fact = %SpeciesMinedFact{text: "x", label: "verified", pmid: "1", reason: ""}
    serialized = FoodJSON.research_fact(fact)

    assert serialized.lay == %{tier: nil, clarity: nil, flags: []}
    assert serialized.reason == nil
  end

  test "species_detail research block carries the tally and the curated split" do
    fact = %SpeciesMinedFact{text: "lab", label: "verified", pmid: "1"}

    research = %{
      counts: %{total: 9, verified: 4, contradicted: 2, unverified: 3},
      relevant: [],
      mechanistic: [fact],
      mechanistic_count: 7
    }

    block =
      FoodJSON.species_detail(%FoundementalFoodSpecies{id: 2, name: "Spinach"}, research, []).data.research

    assert block.counts == %{total: 9, verified: 4, contradicted: 2, unverified: 3}
    assert block.relevant == []
    assert [%{text: "lab"}] = block.mechanistic
    assert block.mechanistic_count == 7
  end

  test "species_detail tolerates an empty research block and flags the default ingredient" do
    ingredients = [%{id: 1, name: "Spinach, cooked"}, %{id: 2, name: "Spinach, raw"}]

    data =
      FoodJSON.species_detail(
        %FoundementalFoodSpecies{id: 2, name: "Spinach"},
        %{},
        ingredients,
        %{},
        default_ingredient: %{id: 2},
        recipes_count: 3
      ).data

    assert data.research.counts == %{total: 0, verified: 0, contradicted: 0, unverified: 0}

    assert data.ingredients == [
             %{id: 1, name: "Spinach, cooked", default: false},
             %{id: 2, name: "Spinach, raw", default: true}
           ]

    assert data.recipes == []
    assert data.recipes_count == 3
  end
end
