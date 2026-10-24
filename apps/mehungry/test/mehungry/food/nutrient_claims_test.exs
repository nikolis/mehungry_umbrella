defmodule Mehungry.Food.NutrientClaimsTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.NutrientClaims, as: Claims

  # A leaf nutrient node, in the string-keyed shape the recipe `nutrients` JSONB
  # reloads as (name / amount / measurement_unit / children).
  defp leaf(name, amount, unit) do
    %{"name" => name, "amount" => amount, "measurement_unit" => unit, "children" => []}
  end

  # The recipe nutrient tree nests vitamins/minerals under umbrella nodes, keyed
  # at the top level by node name (as `put_nutrient_info/2` stores them).
  defp minerals(children), do: %{"Minerals" => umbrella("Minerals", children)}
  defp vitamins(children), do: %{"Vitamins" => umbrella("Vitamins", children)}

  defp umbrella(name, children) do
    %{"name" => name, "amount" => 0.0, "measurement_unit" => "mg", "children" => children}
  end

  describe "badges/3 — thresholds" do
    test "30% of NRV per serving earns a :high badge" do
      # 48 mg vitamin C over 2 servings = 24 mg/serving = 30% of the 80 mg NRV.
      tree = vitamins([leaf("Vitamin C", 48.0, "mg")])

      assert [%{nutrient: "Vitamin C", level: :high, percent_nrv: 30}] =
               Claims.badges(tree, 2)
    end

    test "15% of NRV per serving earns a :source badge" do
      # 4.2 mg iron over 2 servings = 2.1 mg/serving = 15% of the 14 mg NRV.
      tree = minerals([leaf("Iron, Fe", 4.2, "mg")])

      assert [%{nutrient: "Iron", level: :source, percent_nrv: 15}] = Claims.badges(tree, 2)
    end

    test "iron at 30% NRV per serving is :high, not :source" do
      # 8.4 mg iron / 2 = 4.2 mg/serving = 30% of 14 mg.
      tree = minerals([leaf("Iron, Fe", 8.4, "mg")])

      assert [%{nutrient: "Iron", level: :high, percent_nrv: 30}] = Claims.badges(tree, 2)
    end

    test "below 15% earns no badge" do
      # 2 mg iron / 2 = 1 mg/serving ≈ 7% of 14 mg.
      tree = minerals([leaf("Iron, Fe", 2.0, "mg")])

      assert [] = Claims.badges(tree, 2)
    end

    test "level: :high keeps only high badges, dropping source-tier ones" do
      tree = minerals([leaf("Iron, Fe", 4.2, "mg")])

      assert [] = Claims.badges(tree, 2, level: :high)
    end
  end

  describe "badges/3 — coverage gate" do
    # A tree that otherwise clearly earns a badge (iron at 30% NRV per serving).
    defp iron_high_tree, do: minerals([leaf("Iron, Fe", 8.4, "mg")])

    test "coverage below the floor suppresses all badges" do
      assert [] = Claims.badges(iron_high_tree(), 2, coverage: Claims.coverage_floor() - 0.01)
    end

    test "coverage at or above the floor leaves badges intact" do
      assert [%{nutrient: "Iron", level: :high}] =
               Claims.badges(iron_high_tree(), 2, coverage: Claims.coverage_floor())

      assert [%{nutrient: "Iron", level: :high}] =
               Claims.badges(iron_high_tree(), 2, coverage: 1.0)
    end

    test "omitting :coverage is not gated (derive-on-read back-compat)" do
      assert [%{nutrient: "Iron", level: :high}] = Claims.badges(iron_high_tree(), 2)
    end

    test "a non-numeric :coverage is ignored (not gated)" do
      assert [%{nutrient: "Iron", level: :high}] =
               Claims.badges(iron_high_tree(), 2, coverage: nil)
    end
  end

  describe "badges/3 — tree traversal & units" do
    test "finds a mineral nested under the Minerals umbrella (USDA leaf name)" do
      # "Calcium, Ca" normalizes/prefix-matches the "Calcium" label.
      # 480 mg / 1 serving = 60% of the 800 mg NRV.
      tree = minerals([leaf("Calcium, Ca", 480.0, "mg")])

      assert [%{nutrient: "Calcium", level: :high, percent_nrv: 60}] = Claims.badges(tree, 1)
    end

    test "converts µg nutrients against their µg NRV" do
      # Folate NRV 200 µg; 120 µg/serving = 60% → :high. Stored label per
      # NutrientNameNormalizer is "Folate (Vitamin B9)".
      tree = vitamins([leaf("Folate (Vitamin B9)", 120.0, "µg")])

      assert [%{nutrient: "Folate (Vitamin B9)", level: :high, percent_nrv: 60}] =
               Claims.badges(tree, 1)
    end

    test "a nutrient in a non-mass unit (IU) is skipped, not mis-badged" do
      tree = vitamins([leaf("Vitamin A", 5000.0, "IU")])

      assert [] = Claims.badges(tree, 1)
    end

    test "sodium never produces a badge even when abundant" do
      tree = minerals([leaf("Sodium, Na", 5000.0, "mg")])

      assert [] = Claims.badges(tree, 1)
    end

    test "sorts multiple badges by percent_nrv descending" do
      tree = %{
        "Vitamins" => umbrella("Vitamins", [leaf("Vitamin C", 24.0, "mg")]),
        "Minerals" => umbrella("Minerals", [leaf("Calcium, Ca", 480.0, "mg")])
      }

      assert [
               %{nutrient: "Calcium", percent_nrv: 60},
               %{nutrient: "Vitamin C", percent_nrv: 30}
             ] = Claims.badges(tree, 1)
    end
  end

  describe "badges/3 — servings fallback" do
    test "nil / zero servings falls back to the raw total" do
      tree = vitamins([leaf("Vitamin C", 24.0, "mg")])

      assert [%{nutrient: "Vitamin C", percent_nrv: 30}] = Claims.badges(tree, nil)
      assert [%{nutrient: "Vitamin C", percent_nrv: 30}] = Claims.badges(tree, 0)
    end
  end

  describe "badges_for_recipe/2" do
    test "reads the recipe's nutrients tree and servings" do
      recipe = %{nutrients: minerals([leaf("Iron, Fe", 8.4, "mg")]), servings: 2}

      assert [%{nutrient: "Iron", level: :high}] = Claims.badges_for_recipe(recipe)
    end

    test "tolerates a recipe with no nutrients" do
      assert [] = Claims.badges_for_recipe(%{nutrients: nil, servings: 1})
    end
  end

  describe "badges_for_storage/3" do
    test "returns string-keyed maps with a string level (jsonb-ready)" do
      tree = minerals([leaf("Iron, Fe", 8.4, "mg")])

      assert [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 30}] =
               Claims.badges_for_storage(tree, 2)
    end

    test "works on the atom-keyed in-memory tree after a JSON round-trip (write path)" do
      # The shape NutrientHierarchyBuilder produces before Ecto persists it:
      # string top-level keys, atom-keyed nodes. put_nutrient_info/2 round-trips
      # it through JSON (exactly what Ecto stores/reloads) before computing badges.
      atom_tree = %{
        "Minerals" => %{
          name: "Minerals",
          amount: 0.0,
          measurement_unit: "mg",
          children: [
            %{name: "Iron, Fe", amount: 8.4, measurement_unit: "mg", children: []}
          ]
        }
      }

      stringified = atom_tree |> Jason.encode!() |> Jason.decode!()

      assert [%{"nutrient" => "Iron", "level" => "high", "percent_nrv" => 30}] =
               Claims.badges_for_storage(stringified, 2)
    end
  end

  describe "claim slugs" do
    test "claim_slug/1 slugifies labels and drops parenthetical aliases" do
      assert Claims.claim_slug("Vitamin C") == "vitamin-c"
      assert Claims.claim_slug("Iron") == "iron"
      assert Claims.claim_slug("Folate (Vitamin B9)") == "folate"
      assert Claims.claim_slug("Vitamin B1 (Thiamin)") == "vitamin-b1"
    end

    test "label_for_slug/1 is the inverse of claim_slug/1 for every NRV nutrient" do
      for {label, _} <- Claims.nrv() do
        assert Claims.label_for_slug(Claims.claim_slug(label)) == label
      end
    end

    test "label_for_slug/1 is nil for an unknown or non-binary slug" do
      assert is_nil(Claims.label_for_slug("unobtainium"))
      assert is_nil(Claims.label_for_slug(nil))
    end

    test "slugs are unique across the NRV set (no collisions)" do
      slugs = Claims.claim_slugs() |> Map.keys()
      assert length(slugs) == map_size(Claims.nrv())
    end
  end

  describe "nrv table" do
    test "nrv_grams/1 converts the NRV to grams" do
      assert_in_delta Claims.nrv_grams("Iron"), 0.014, 1.0e-9
      assert_in_delta Claims.nrv_grams("Calcium"), 0.8, 1.0e-9
    end

    test "nrv_grams/1 is nil for an unknown label" do
      assert is_nil(Claims.nrv_grams("Unobtainium"))
    end
  end
end
