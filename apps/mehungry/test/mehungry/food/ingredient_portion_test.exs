defmodule Mehungry.Food.IngredientPortionTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.{IngredientPortion, MeasurementUnit}

  describe "strip_amount/1" do
    test "drops a leading quantity from an English label" do
      assert IngredientPortion.strip_amount("1 cup") == "cup"
      assert IngredientPortion.strip_amount("2 tablespoons") == "tablespoons"
    end

    test "drops a leading quantity from a Greek label" do
      assert IngredientPortion.strip_amount("1 φλιτζάνι") == "φλιτζάνι"
    end

    test "removes fractions and decimals, including comma decimals" do
      assert IngredientPortion.strip_amount("2 1/2 cups") == "cups"
      assert IngredientPortion.strip_amount("1.5 cups") == "cups"
      assert IngredientPortion.strip_amount("1,5 φλιτζάνι") == "φλιτζάνι"
    end

    test "cleans orphaned separators left behind" do
      assert IngredientPortion.strip_amount("8-ounce") == "ounce"
    end

    test "keeps a label that has no quantity" do
      assert IngredientPortion.strip_amount("medium banana") == "medium banana"
    end

    test "returns the original when stripping would empty it" do
      assert IngredientPortion.strip_amount("12") == "12"
    end

    test "passes through non-binaries" do
      assert IngredientPortion.strip_amount(nil) == nil
    end
  end

  describe "display_name/1" do
    test "strips the quantity from a free-text description" do
      assert IngredientPortion.display_name(%IngredientPortion{description: "1 cup"}) == "cup"
    end

    test "falls back to the measurement unit name, also stripped" do
      portion = %IngredientPortion{description: nil, measurement_unit: %MeasurementUnit{name: "cup"}}
      assert IngredientPortion.display_name(portion) == "cup"
    end

    test "nil when there is neither a description nor a unit" do
      assert IngredientPortion.display_name(%IngredientPortion{}) == nil
    end
  end
end
