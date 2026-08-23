defmodule Mehungry.Food.NutrientMergerTest do
  @moduledoc """
  Coverage for `Mehungry.Food.NutrientMerger` — the shared nutrient-name and
  key primitives (`normalize_nutrient_name/1`, `to_string_keys/1`,
  `to_atom_keys/1`) used by the stored-recipe display path. See
  `docs/food/nutrition_calculation.md`.
  """
  use ExUnit.Case, async: true

  alias Mehungry.Food.NutrientMerger, as: NM

  describe "normalize_nutrient_name/1" do
    test "maps synonyms to canonical names" do
      assert NM.normalize_nutrient_name("total lipid (fat)") == "Total Fat"
      assert NM.normalize_nutrient_name("carbohydrate, by difference") == "Carbohydrates"
      assert NM.normalize_nutrient_name("kilojoule") == "Energy"
      assert NM.normalize_nutrient_name("fatty acids, total saturated") == "Saturated Fat"
    end

    test "accepts atoms and nil, capitalizing unknowns" do
      assert NM.normalize_nutrient_name(:protein) == "Protein"
      assert NM.normalize_nutrient_name(nil) == "Unknown"
      assert NM.normalize_nutrient_name("weird stuff") == "Weird Stuff"
    end
  end

  describe "to_string_keys/1 and to_atom_keys/1" do
    test "round-trips a nested nutrient map" do
      atom_map = %{name: "Total Fat", amount: 5.0, children: [%{name: "Saturated Fat"}]}

      string_map = NM.to_string_keys(atom_map)

      assert string_map == %{
               "name" => "Total Fat",
               "amount" => 5.0,
               "children" => [%{"name" => "Saturated Fat"}]
             }

      back = NM.to_atom_keys(string_map)
      assert back[:name] == "Total Fat"
      assert [%{name: "Saturated Fat"}] = back[:children]
    end

    test "passes nil and scalars through" do
      assert NM.to_string_keys(nil) == nil
      assert NM.to_atom_keys("x") == "x"
    end
  end
end
