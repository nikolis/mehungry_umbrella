defmodule Mehungry.NutrientUtilsTest do
  use ExUnit.Case, async: true

  alias Mehungry.NutrientUtils, as: Nu

  describe "to_grams/2" do
    test "keeps grams unchanged" do
      assert {:ok, 20.0} = Nu.to_grams(20, "g")
      assert {:ok, 20.0} = Nu.to_grams(20, "grams")
    end

    test "converts milligrams to grams" do
      assert {:ok, grams} = Nu.to_grams(500, "mg")
      assert_in_delta grams, 0.5, 1.0e-9
    end

    test "converts micrograms to grams (µg / mcg / ug)" do
      for unit <- ["µg", "mcg", "ug"] do
        assert {:ok, grams} = Nu.to_grams(900, unit)
        assert_in_delta grams, 0.0009, 1.0e-9
      end
    end

    test "is case- and whitespace-insensitive on the unit" do
      assert {:ok, 1.0} = Nu.to_grams(1000, " MG ")
    end

    test "returns :error for non-mass units" do
      assert :error = Nu.to_grams(200, "kcal")
      assert :error = Nu.to_grams(300, "IU")
    end

    test "returns :error for a missing or non-string unit" do
      assert :error = Nu.to_grams(5, nil)
      assert :error = Nu.to_grams(5, "")
    end

    test "returns :error when amount is not a number" do
      assert :error = Nu.to_grams(nil, "g")
    end
  end

  describe "macronutrient?/1" do
    test "classifies macronutrients (incl. fat subtypes) as true" do
      for label <- [
            "Protein",
            "Carbohydrates",
            "Total Fat",
            "Saturated Fat",
            "Total Sugars",
            "Added Sugars",
            "Fiber"
          ] do
        assert Nu.macronutrient?(label), "expected #{label} to be a macronutrient"
      end
    end

    test "classifies vitamins and minerals as micronutrients (false)" do
      for label <- ["Sodium", "Calcium", "Iron", "Potassium", "Vitamin C", "Cholesterol"] do
        refute Nu.macronutrient?(label), "expected #{label} to be a micronutrient"
      end
    end

    test "is case-insensitive" do
      assert Nu.macronutrient?("total fat")
    end

    test "returns false for non-binary input" do
      refute Nu.macronutrient?(nil)
    end
  end
end
