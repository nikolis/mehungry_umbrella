defmodule Mehungry.Food.RecipeUtilsTest do
  @moduledoc """
  Coverage for the two surviving display helpers in
  `Mehungry.Food.RecipeUtils` (the calc/aggregation code moved to
  `NutrientCalculation` / `NutrientUtils`). See `docs/food/nutrition_calculation.md`.
  """
  use ExUnit.Case, async: true

  alias Mehungry.Food.RecipeUtils

  describe "sort_nutrients_from_db/1" do
    test "floats headline nutrients to the top, keeps the rest, and indexes them" do
      nutrients = [
        {"Zinc", %{}},
        {"Energy", %{}},
        {"Protein", %{}},
        {"Total lipid (fat)", %{}}
      ]

      sorted = RecipeUtils.sort_nutrients_from_db(nutrients)

      # Returns {tuple, index} pairs, primaries first in the canonical order.
      names_in_order = Enum.map(sorted, fn {{name, _}, _idx} -> name end)
      assert names_in_order == ["Energy", "Total lipid (fat)", "Protein", "Zinc"]

      # Indices are 0-based and contiguous.
      assert Enum.map(sorted, fn {_pair, idx} -> idx end) == [0, 1, 2, 3]
    end

    test "leaves an all-secondary list in place (just indexed)" do
      nutrients = [{"Zinc", %{}}, {"Copper", %{}}]
      sorted = RecipeUtils.sort_nutrients_from_db(nutrients)
      assert Enum.map(sorted, fn {{name, _}, _} -> name end) == ["Zinc", "Copper"]
    end
  end

  describe "reform_nutrients/1" do
    test "re-keys by name with string keys and flattens the unit struct to its name" do
      nutrients = [
        %{name: "Protein", amount: 10.0, measurement_unit: %{name: "g"}},
        %{name: "Energy", amount: 100.0, measurement_unit: %{name: "kcal"}}
      ]

      reformed = RecipeUtils.reform_nutrients(nutrients)

      assert reformed["Protein"]["amount"] == 10.0
      assert reformed["Protein"]["measurement_unit"] == "g"
      assert reformed["Energy"]["measurement_unit"] == "kcal"
      assert reformed["Energy"]["name"] == "Energy"
    end
  end
end
