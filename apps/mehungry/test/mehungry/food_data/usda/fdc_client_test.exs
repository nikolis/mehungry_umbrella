defmodule Mehungry.FoodData.Usda.FdcClientTest do
  use ExUnit.Case, async: true

  alias Mehungry.FoodData.Usda.FdcClient

  # Foundation foods the public FDC detail API 404s on are recovered from the
  # website's own (undocumented) `/portal-data/external/{fdcId}` endpoint, whose
  # JSON shape differs from the public API. `adapt_portal_food/1` maps it into
  # the format `FoodParser.reconcile_ingredient/2` consumes. This fixture is a
  # trimmed-but-faithful capture of the real portal response for fdcId 333281
  # ("Tomatoes, canned, red, ripe, diced"); if USDA changes the portal shape,
  # these assertions fail instead of the worker silently writing empty payloads.
  describe "adapt_portal_food/1" do
    setup do
      json =
        [__DIR__, "..", "..", "..", "fixtures", "usda_portal_food_333281.json"]
        |> Path.join()
        |> File.read!()
        |> Jason.decode!()

      %{attrs: FdcClient.adapt_portal_food(json)}
    end

    test "maps portal field names onto the public-API shape", %{attrs: attrs} do
      assert attrs["description"] == "Tomatoes, canned, red, ripe, diced"
      assert attrs["fdcId"] == 333_281
      assert attrs["ndbNumber"] == 100_193
      # dataType/foodCategory/publicationDate are null in the portal record and
      # are backfilled from foodType/foodGroup/lastUpdated respectively.
      assert attrs["dataType"] == "Foundation"
      assert attrs["foodClass"] == "FinalFood"
      assert attrs["foodCategory"] == %{"description" => "Vegetables and Vegetable Products"}
      assert attrs["publicationDate"] == "4/1/2019"
    end

    test "extracts valued nutrients and drops label + value-less rows", %{attrs: attrs} do
      nutrients = attrs["foodNutrients"]

      # The "Proximates" label row and the synthetic value-less row are filtered;
      # only the three valued nutrients survive.
      names = Enum.map(nutrients, & &1["nutrient"]["name"])
      refute "Proximates" in names
      refute "Missing Value Nutrient" in names
      assert length(nutrients) == 3

      by_name = Map.new(nutrients, &{&1["nutrient"]["name"], &1})

      water = by_name["Water"]
      assert water["amount"] == 94.6
      assert water["nutrient"]["unitName"] == "g"
      assert water["nutrient"]["number"] == "255"
      assert water["type"] == "FoodNutrient"

      assert by_name["Sodium, Na"]["amount"] == 125
      assert by_name["Sodium, Na"]["nutrient"]["unitName"] == "mg"

      # Every emitted nutrient carries a numeric amount, an id, and a unit.
      assert Enum.all?(nutrients, fn n ->
               is_number(n["amount"]) and not is_nil(n["nutrient"]["id"]) and
                 not is_nil(n["nutrient"]["unitName"])
             end)
    end

    test "maps foodMeasures to portions with distinct sequence numbers", %{attrs: attrs} do
      portions = attrs["foodPortions"]
      assert length(portions) == 3

      cup = Enum.find(portions, &(&1["modifier"] == "cup"))
      assert cup["gramWeight"] == 245.0
      assert cup["value"] == 245.0
      assert cup["amount"] == 1.0

      # An "undetermined" measureUnit is unusable, so the descriptive modifier
      # text ("piece") is used instead of the placeholder unit name.
      piece = Enum.find(portions, &(&1["modifier"] == "piece"))
      assert piece["gramWeight"] == 28.0

      # Sequence numbers are the ordinal position, so they stay distinct even
      # though the portal ranks can collide.
      assert Enum.map(portions, & &1["sequenceNumber"]) == [1, 2, 3]
    end
  end
end
