defmodule MehungryWeb.Api.V1.FoodJSONTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.FoundementalFoodSpecies
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
end
