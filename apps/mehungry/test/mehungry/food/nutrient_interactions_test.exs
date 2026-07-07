defmodule Mehungry.Food.NutrientInteractionsTest do
  use Mehungry.DataCase

  alias Mehungry.Food
  alias Mehungry.Food.NutrientInteractions
  alias Mehungry.FoodFixtures

  # Amounts per 100g that sit comfortably above each threshold.
  @above_iron 2.0
  @above_vitamin_c 10.0
  @above_calcium 140.0
  @above_fat 6.0
  @above_vitamin_k 13.0
  @above_vitamin_d 2.5
  @above_magnesium 45.0
  @above_folate 45.0

  # Below every threshold — should never trigger a rule.
  @below 0.1

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp nutrient_fixture(name, rank) do
    {:ok, nutrient} = Food.create_nutrient(%{name: name, rank: rank})
    nutrient
  end

  defp add_nutrient(ingredient, name, amount, rank \\ 1) do
    nutrient = nutrient_fixture(name, rank)

    {:ok, _} =
      Food.create_ingredient_nutrient(%{
        ingredient_id: ingredient.id,
        nutrient_id: nutrient.id,
        amount: amount
      })
  end

  # ── Tests ─────────────────────────────────────────────────────────────────

  describe "interactions_for_ingredients/1" do
    test "returns empty list for an empty ingredient list" do
      assert NutrientInteractions.interactions_for_ingredients([]) == []
    end

    test "returns empty list when no nutrient amounts reach threshold" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Iron", @below, 1)
      add_nutrient(ingredient, "Vitamin C", @below, 2)

      assert NutrientInteractions.interactions_for_ingredients([ingredient.id]) == []
    end

    test "returns empty list when only nutrient_b is present without nutrient_a" do
      ingredient = FoodFixtures.ingredient_fixture()
      # Calcium present but no Iron — :calcium_inhibits_iron must not fire
      add_nutrient(ingredient, "Calcium", @above_calcium)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      refute Enum.any?(result, &(&1.id == :calcium_inhibits_iron))
    end

    test "fires :vitamin_c_enhances_iron when both are significant in one ingredient" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Iron", @above_iron, 1)
      add_nutrient(ingredient, "Vitamin C", @above_vitamin_c, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :vitamin_c_enhances_iron))

      assert interaction != nil
      assert interaction.badge == :positive
      assert interaction.type == :enhances
      assert ingredient.id in interaction.source_ingredient_ids
      assert ingredient.id in interaction.interacting_ingredient_ids
    end

    test "fires :vitamin_c_enhances_iron across two ingredients" do
      spinach = FoodFixtures.ingredient_fixture()
      lemon = FoodFixtures.ingredient_fixture()

      add_nutrient(spinach, "Iron", @above_iron)
      add_nutrient(lemon, "Vitamin C", @above_vitamin_c)

      result = NutrientInteractions.interactions_for_ingredients([spinach.id, lemon.id])
      interaction = Enum.find(result, &(&1.id == :vitamin_c_enhances_iron))

      assert interaction != nil
      assert spinach.id in interaction.source_ingredient_ids
      assert lemon.id in interaction.interacting_ingredient_ids
    end

    test "fires :calcium_inhibits_iron with warning badge" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Iron", @above_iron, 1)
      add_nutrient(ingredient, "Calcium", @above_calcium, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :calcium_inhibits_iron))

      assert interaction != nil
      assert interaction.badge == :warning
      assert interaction.type == :inhibits
    end

    test "fires :vitamin_d_enhances_calcium with positive badge" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Calcium", @above_calcium, 1)
      add_nutrient(ingredient, "Vitamin D", @above_vitamin_d, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :vitamin_d_enhances_calcium))

      assert interaction != nil
      assert interaction.badge == :positive
    end

    test "fires :fat_required_for_vitamin_k as a tip when fat is absent" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Vitamin K", @above_vitamin_k)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :fat_required_for_vitamin_k))

      assert interaction != nil
      assert interaction.badge == :tip
      assert interaction.type == :requires
      assert interaction.missing_nutrient == "Total Fat"
      refute Map.has_key?(interaction, :interacting_ingredient_ids)
    end

    test "shows positive badge for :fat_required_for_vitamin_k when fat is already present" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Vitamin K", @above_vitamin_k, 1)
      add_nutrient(ingredient, "Total Fat", @above_fat, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :fat_required_for_vitamin_k))

      assert interaction != nil
      assert interaction.badge == :positive
      assert interaction.type == :requires
      refute Map.has_key?(interaction, :missing_nutrient)
    end

    test "fires :magnesium_enhances_vitamin_d when both present" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Vitamin D", @above_vitamin_d, 1)
      add_nutrient(ingredient, "Magnesium", @above_magnesium, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :magnesium_enhances_vitamin_d))

      assert interaction != nil
      assert interaction.badge == :positive
    end

    test "fires :vitamin_c_enhances_folate when both present" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Folate", @above_folate, 1)
      add_nutrient(ingredient, "Vitamin C", @above_vitamin_c, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      interaction = Enum.find(result, &(&1.id == :vitamin_c_enhances_folate))

      assert interaction != nil
      assert interaction.badge == :positive
    end

    test "can fire multiple rules simultaneously" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Iron", @above_iron, 1)
      add_nutrient(ingredient, "Vitamin C", @above_vitamin_c, 2)
      add_nutrient(ingredient, "Calcium", @above_calcium, 3)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      ids = Enum.map(result, & &1.id)

      assert :vitamin_c_enhances_iron in ids
      assert :calcium_inhibits_iron in ids
    end

    test "only issues one result per matching rule" do
      ingredient = FoodFixtures.ingredient_fixture()
      add_nutrient(ingredient, "Iron", @above_iron, 1)
      add_nutrient(ingredient, "Vitamin C", @above_vitamin_c, 2)

      result = NutrientInteractions.interactions_for_ingredients([ingredient.id])
      matching = Enum.filter(result, &(&1.id == :vitamin_c_enhances_iron))

      assert length(matching) == 1
    end
  end

  describe "interactions_for_nutrient_map/1" do
    test "returns empty list for an empty map" do
      assert NutrientInteractions.interactions_for_nutrient_map(%{}) == []
    end

    test "returns empty list when no amounts reach threshold" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{"Iron" => 0.1, "Vitamin C" => 0.1})

      assert result == []
    end

    test "returns empty list when only nutrient_b is present without nutrient_a" do
      result = NutrientInteractions.interactions_for_nutrient_map(%{"Calcium" => 200.0})
      refute Enum.any?(result, &(&1.id == :calcium_inhibits_iron))
    end

    test "fires :vitamin_c_enhances_iron with positive badge" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{
          "Iron" => 2.0,
          "Vitamin C" => 10.0
        })

      interaction = Enum.find(result, &(&1.id == :vitamin_c_enhances_iron))

      assert interaction != nil
      assert interaction.badge == :positive
      assert interaction.type == :enhances
    end

    test "fires :calcium_inhibits_iron with warning badge" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{
          "Iron" => 2.0,
          "Calcium" => 140.0
        })

      interaction = Enum.find(result, &(&1.id == :calcium_inhibits_iron))

      assert interaction != nil
      assert interaction.badge == :warning
      assert interaction.type == :inhibits
    end

    test "fires :fat_required_for_vitamin_d as tip when fat is absent" do
      result = NutrientInteractions.interactions_for_nutrient_map(%{"Vitamin D" => 3.0})
      interaction = Enum.find(result, &(&1.id == :fat_required_for_vitamin_d))

      assert interaction != nil
      assert interaction.badge == :tip
      assert interaction.missing_nutrient == "Total Fat"
    end

    test "fires :fat_required_for_vitamin_d as positive when fat is present" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{
          "Vitamin D" => 3.0,
          "Total Fat" => 37.0
        })

      interaction = Enum.find(result, &(&1.id == :fat_required_for_vitamin_d))

      assert interaction != nil
      assert interaction.badge == :positive
      refute Map.has_key?(interaction, :missing_nutrient)
    end

    test "does not fire :requires tip when only fat is present without the vitamin" do
      result = NutrientInteractions.interactions_for_nutrient_map(%{"Total Fat" => 37.0})
      refute Enum.any?(result, &(&1.type == :requires))
    end

    test "can fire multiple rules simultaneously" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{
          "Iron" => 2.0,
          "Vitamin C" => 10.0,
          "Calcium" => 140.0
        })

      ids = Enum.map(result, & &1.id)

      assert :vitamin_c_enhances_iron in ids
      assert :calcium_inhibits_iron in ids
    end

    test "only issues one result per matching rule" do
      result =
        NutrientInteractions.interactions_for_nutrient_map(%{
          "Iron" => 2.0,
          "Vitamin C" => 10.0
        })

      matching = Enum.filter(result, &(&1.id == :vitamin_c_enhances_iron))

      assert length(matching) == 1
    end
  end
end
