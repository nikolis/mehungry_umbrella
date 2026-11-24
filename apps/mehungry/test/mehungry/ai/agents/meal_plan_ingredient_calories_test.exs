defmodule Mehungry.AI.Agents.MealPlanIngredientCaloriesTest do
  @moduledoc """
  `search_ingredients` hands the model calories for every unit option, and
  `submit_plan` counts an ingredient entry (kcal_per_unit × quantity) toward the
  day's total — so snacks are no longer chosen blind.
  """
  use Mehungry.DataCase, async: true

  alias Mehungry.AI.Agents.MealPlanCore
  alias Mehungry.Food.{IngredientNutrient, MeasurementUnit, Nutrient}
  alias Mehungry.{FoodFixtures, Repo}

  @day ~D[2030-01-07]
  @date "2030-01-07"

  setup do
    gram = FoodFixtures.measurement_unit_fixture()
    kcal = Repo.insert!(%MeasurementUnit{name: "kcal_#{System.unique_integer([:positive])}"})

    energy =
      Repo.insert!(%Nutrient{name: "Energy", number: "208", measurement_unit_id: kcal.id})

    ingredient = FoodFixtures.ingredient_fixture(%{name: "zzqalmond kernels"})

    Repo.insert!(%IngredientNutrient{
      ingredient_id: ingredient.id,
      nutrient_id: energy.id,
      amount: 600.0
    })

    %{ingredient: ingredient, gram: gram}
  end

  defp acc(band) do
    %{
      start_date: @day,
      guards: MealPlanCore.guards(catalog: :public),
      offered: MapSet.new(),
      offered_ingredients: MapSet.new(),
      calorie_band: band,
      submitted: nil
    }
  end

  test "each unit option carries kcal_per_unit, and the entry counts toward the day", %{
    ingredient: ingredient,
    gram: gram
  } do
    {result, acc} =
      MealPlanCore.search_ingredients_tool("zzqalmond", acc(%{min: 170, max: 190, aim: 180}))

    assert result.found
    assert found = Enum.find(result.ingredients, &(&1.ingredient_id == ingredient.id))
    assert found.kcal_per_100g == 600

    assert %{kcal_per_unit: 6.0} = Enum.find(found.units, &(&1.unit_selection == gram.id))

    entry = fn grams ->
      %{
        "date" => @date,
        "slot" => "Morning Snack",
        "ingredient_id" => ingredient.id,
        "unit_selection" => gram.id,
        "quantity" => grams
      }
    end

    # 20 g × 6 kcal = 120 → under 170–190; the quantity is rebalanced in 5 g
    # steps (within 0.5–1.5× of the model's choice) to 30 g = 180 kcal.
    {result, acc} = MealPlanCore.submit_plan_tool(%{"entries" => [entry.(20)]}, acc)

    assert result.success
    assert [%{ingredient_id: id, quantity: 30.0}] = flat_entries(acc)
    assert id == ingredient.id

    # 200 g is far over and can only come down to 100 g = 600 kcal → rejected.
    {high, _acc} = MealPlanCore.submit_plan_tool(%{"entries" => [entry.(200)]}, acc)
    refute high.success
    assert hd(high.errors) =~ "totals 600 kcal"
  end

  # Normalized entries hold `items`; these tests plan one item per meal, so read
  # each meal as its single item merged onto the meal.
  defp flat_entries(acc),
    do: Enum.map(acc.submitted.entries, &Map.merge(Map.delete(&1, :items), hd(&1.items)))
end
