defmodule Mehungry.PortionGenerationTest do
  use Mehungry.DataCase

  import Mehungry.FoodFixtures

  alias Mehungry.Repo
  alias Mehungry.Food
  alias Mehungry.Food.{IngredientPortion, MeasurementUnit, PortionConversion}

  defp seed_portion(ingredient, unit, gram_weight) do
    Repo.insert!(%IngredientPortion{
      ingredient_id: ingredient.id,
      measurement_unit_id: unit.id,
      gram_weight: gram_weight,
      amount: 1.0
    })
  end

  # Returns %{canonical_token => gram_weight} for all of an ingredient's portions.
  # Keys are canonicalized (a reused "teaspoon" unit and a minted "tsp" both key
  # on "tsp") so assertions don't depend on which spelling already existed.
  defp portions_by_unit(ingredient_id) do
    from(ip in IngredientPortion,
      join: mu in MeasurementUnit,
      on: mu.id == ip.measurement_unit_id,
      where: ip.ingredient_id == ^ingredient_id,
      select: {mu.name, ip.gram_weight}
    )
    |> Repo.all()
    |> Map.new(fn {name, gw} -> {PortionConversion.canonical_unit(name), gw} end)
  end

  describe "PortionConversion.grams_per_ml/1" do
    test "derives density from a cup=240 g anchor" do
      ingredient = ingredient_fixture()
      cup = measurement_unit_fixture(%{name: "cup"})
      seed_portion(ingredient, cup, 240.0)

      assert {:ok, gpml} = PortionConversion.grams_per_ml(ingredient.id)
      assert_in_delta gpml, 1.0, 0.0001
    end

    test "returns :none when the ingredient has no volume portion" do
      ingredient = ingredient_fixture()
      oz = measurement_unit_fixture(%{name: "oz"})
      seed_portion(ingredient, oz, 28.35)

      assert PortionConversion.grams_per_ml(ingredient.id) == :none
    end

    test "returns :none when the ingredient has no portions at all" do
      ingredient = ingredient_fixture()
      assert PortionConversion.grams_per_ml(ingredient.id) == :none
    end
  end

  describe "generate_portions_for_ingredient/1" do
    test "creates the kg mass portion (1000 g), independent of any anchor" do
      ingredient = ingredient_fixture()

      created = Food.generate_portions_for_ingredient(ingredient.id)

      by_unit = portions_by_unit(ingredient.id)
      assert Map.fetch!(by_unit, "kg") == 1000.0
      # No volume anchor → only the mass unit is created.
      assert created == 1
      refute Map.has_key?(by_unit, "tsp")
      refute Map.has_key?(by_unit, "cup")
    end

    test "derives tsp/tbsp/cup/ml/l gram weights from a cup=240 g anchor" do
      ingredient = ingredient_fixture()
      cup = measurement_unit_fixture(%{name: "cup"})
      seed_portion(ingredient, cup, 240.0)

      Food.generate_portions_for_ingredient(ingredient.id)
      by_unit = portions_by_unit(ingredient.id)

      # density 1.0 g/ml → volume units scale by their ml.
      assert_in_delta Map.fetch!(by_unit, "ml"), 1.0, 0.0001
      assert_in_delta Map.fetch!(by_unit, "tsp"), 5.0, 0.0001
      assert_in_delta Map.fetch!(by_unit, "tbsp"), 15.0, 0.0001
      assert_in_delta Map.fetch!(by_unit, "liter"), 1000.0, 0.0001
      assert Map.fetch!(by_unit, "kg") == 1000.0
      # The pre-existing cup anchor is untouched (not duplicated).
      assert_in_delta Map.fetch!(by_unit, "cup"), 240.0, 0.0001
    end

    test "is idempotent — a second run creates nothing" do
      ingredient = ingredient_fixture()
      cup = measurement_unit_fixture(%{name: "cup"})
      seed_portion(ingredient, cup, 240.0)

      first = Food.generate_portions_for_ingredient(ingredient.id)
      assert first > 0

      before = portions_by_unit(ingredient.id)
      second = Food.generate_portions_for_ingredient(ingredient.id)

      assert second == 0
      assert portions_by_unit(ingredient.id) == before
    end

    test "non-unit (density ≠ 1) anchor scales correctly" do
      ingredient = ingredient_fixture()
      cup = measurement_unit_fixture(%{name: "cup"})
      # 1 cup = 120 g → density 0.5 g/ml.
      seed_portion(ingredient, cup, 120.0)

      Food.generate_portions_for_ingredient(ingredient.id)
      by_unit = portions_by_unit(ingredient.id)

      assert_in_delta Map.fetch!(by_unit, "tsp"), 2.5, 0.0001
      assert_in_delta Map.fetch!(by_unit, "tbsp"), 7.5, 0.0001
      assert_in_delta Map.fetch!(by_unit, "ml"), 0.5, 0.0001
    end
  end
end
