defmodule Mehungry.History.MealTypeTest do
  use ExUnit.Case, async: true

  alias Mehungry.History.MealType

  test "values/0 and ordered/0 are the 5 canonical snake_case types in order" do
    assert MealType.values() == ~w(breakfast morning_snack lunch afternoon_snack dinner)
    assert MealType.ordered() == MealType.values()
  end

  test "valid?/1 accepts known values and nil (unsorted), rejects others" do
    for v <- MealType.values(), do: assert(MealType.valid?(v))
    assert MealType.valid?(nil)
    refute MealType.valid?("brunch")
  end

  test "label/1 humanizes values and maps nil/unknown to Unsorted" do
    assert MealType.label("breakfast") == "Breakfast"
    assert MealType.label("morning_snack") == "Morning Snack"
    assert MealType.label("afternoon_snack") == "Afternoon Snack"
    assert MealType.label("dinner") == "Dinner"
    assert MealType.label(nil) == "Unsorted"
    assert MealType.label("brunch") == "Unsorted"
  end

  test "from_slot/1 maps AI slot strings to canonical values, else nil" do
    assert MealType.from_slot("Breakfast") == "breakfast"
    assert MealType.from_slot("Lunch") == "lunch"
    assert MealType.from_slot("Dinner") == "dinner"
    assert MealType.from_slot("Snack") == nil
    assert MealType.from_slot(nil) == nil
  end

  test "vocabulary stays in sync with the AI bot's meal_types (drift guard)" do
    assert MealType.values() == Mehungry.AI.Bot.AiBotConfig.meal_types()
  end
end
