defmodule MehungryWeb.Api.V1.JSON.HelpersTest do
  use ExUnit.Case, async: true

  alias MehungryWeb.Api.V1.JSON.Helpers

  describe "localize_nutrients/2 canonical_name" do
    @tree %{
      "Protein" => %{"name" => "Protein", "amount" => 10.0, "measurement_unit" => "gram"},
      "Total Fat" => %{
        "name" => "Total Fat",
        "amount" => 20.0,
        "measurement_unit" => "gram",
        "children" => [
          %{"name" => "Saturated Fat", "amount" => 5.0, "measurement_unit" => "gram"}
        ]
      }
    }

    test "English: canonical_name equals name on every node, at every depth" do
      out = Helpers.localize_nutrients(@tree, "en")

      assert out["Protein"]["canonical_name"] == "Protein"
      assert out["Total Fat"]["canonical_name"] == "Total Fat"

      assert [%{"name" => "Saturated Fat", "canonical_name" => "Saturated Fat"}] =
               out["Total Fat"]["children"]
    end

    test "Greek: name and keys are translated, canonical_name stays English" do
      out = Helpers.localize_nutrients(@tree, "el")

      assert %{"name" => "Πρωτεΐνη", "canonical_name" => "Protein"} = out["Πρωτεΐνη"]
      assert %{"name" => "Ολικά λιπαρά", "canonical_name" => "Total Fat"} = out["Ολικά λιπαρά"]

      assert [%{"name" => "Κορεσμένα λιπαρά", "canonical_name" => "Saturated Fat"}] =
               out["Ολικά λιπαρά"]["children"]
    end

    test "a top-level node without its own name falls back to the map key" do
      out = Helpers.localize_nutrients(%{"Protein" => %{"amount" => 1.0}}, "en")
      assert out["Protein"]["canonical_name"] == "Protein"
    end

    test "atom-keyed nodes get an atom canonical_name key" do
      out = Helpers.localize_nutrients(%{"Protein" => %{name: "Protein", amount: 1.0}}, "el")
      assert %{name: "Πρωτεΐνη", canonical_name: "Protein"} = out["Πρωτεΐνη"]
    end

    test "nil and empty maps stay empty" do
      assert Helpers.localize_nutrients(nil, "el") == %{}
      assert Helpers.localize_nutrients(%{}, "el") == %{}
    end
  end
end
