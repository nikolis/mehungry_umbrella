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

    # 20 g × 6 kcal = 120 → under 170–190.
    {low, acc} = MealPlanCore.submit_plan_tool(%{"entries" => [entry.(20)]}, acc)
    refute low.success
    assert hd(low.errors) =~ "totals 120 kcal"

    # 30 g × 6 kcal = 180 → inside.
    {ok, _acc} = MealPlanCore.submit_plan_tool(%{"entries" => [entry.(30)]}, acc)
    assert ok.success
  end
end
