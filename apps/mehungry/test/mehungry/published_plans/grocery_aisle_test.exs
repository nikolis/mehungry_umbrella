defmodule Mehungry.PublishedPlans.GroceryAisleTest do
  @moduledoc """
  The keyword classifier that maps USDA / dev-seed food categories onto friendly
  shopping aisles for the weekly grocery list.
  """
  use ExUnit.Case, async: true

  alias Mehungry.PublishedPlans.GroceryAisle

  describe "classify/2" do
    test "maps USDA FDC category descriptions to aisles" do
      assert GroceryAisle.classify("Vegetables and Vegetable Products") == "produce"
      assert GroceryAisle.classify("Fruits and Fruit Juices") == "produce"
      assert GroceryAisle.classify("Dairy and Egg Products") == "dairy_eggs"
      assert GroceryAisle.classify("Poultry Products") == "meat_seafood"
      assert GroceryAisle.classify("Beef Products") == "meat_seafood"
      assert GroceryAisle.classify("Finfish and Shellfish Products") == "meat_seafood"
      assert GroceryAisle.classify("Cereal Grains and Pasta") == "bakery_grains"
      assert GroceryAisle.classify("Baked Products") == "bakery_grains"
      assert GroceryAisle.classify("Legumes and Legume Products") == "pantry"
      assert GroceryAisle.classify("Fats and Oils") == "pantry"
      assert GroceryAisle.classify("Spices and Herbs") == "spices"
      assert GroceryAisle.classify("Beverages") == "beverages"
    end

    test "maps the short dev-seed category names too" do
      assert GroceryAisle.classify("Vegetables") == "produce"
      assert GroceryAisle.classify("Dairy") == "dairy_eggs"
      assert GroceryAisle.classify("Meats") == "meat_seafood"
      assert GroceryAisle.classify("Fish") == "meat_seafood"
      assert GroceryAisle.classify("Oils") == "pantry"
      assert GroceryAisle.classify("Nuts") == "pantry"
      assert GroceryAisle.classify("Spices") == "spices"
      assert GroceryAisle.classify("Alcohol") == "beverages"
    end

    test "unknown / generic / nil categories fall back to other" do
      assert GroceryAisle.classify(nil) == "other"
      assert GroceryAisle.classify("General") == "other"
      assert GroceryAisle.classify("Fast Foods") == "other"
      assert GroceryAisle.classify("Restaurant Foods") == "other"
      assert GroceryAisle.classify("") == "other"
    end

    test "ordered/0 lists every aisle with a label, 'other' last" do
      keys = Enum.map(GroceryAisle.ordered(), fn {k, _l} -> k end)
      assert "produce" in keys
      assert List.last(keys) == "other"
      assert Enum.all?(GroceryAisle.ordered(), fn {_k, l} -> is_binary(l) and l != "" end)
    end
  end
end
