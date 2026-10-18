defmodule MehungryWeb.MealTypeLabelsTest do
  use ExUnit.Case, async: true

  alias MehungryWeb.MealTypeLabels

  describe "label/2" do
    test "returns canonical English for en / nil locale" do
      assert MealTypeLabels.label("breakfast", "en") == "Breakfast"
      assert MealTypeLabels.label("afternoon_snack", nil) == "Afternoon Snack"
      assert MealTypeLabels.label(nil, "en") == "Unsorted"
    end

    test "translates every slot to Greek" do
      assert MealTypeLabels.label("breakfast", "el") == "Πρωινό"
      assert MealTypeLabels.label("morning_snack", "el") == "Πρωινό σνακ"
      assert MealTypeLabels.label("lunch", "el") == "Μεσημεριανό"
      assert MealTypeLabels.label("afternoon_snack", "el") == "Απογευματινό σνακ"
      assert MealTypeLabels.label("dinner", "el") == "Βραδινό"
      assert MealTypeLabels.label(nil, "el") == "Χωρίς κατηγορία"
    end

    test "unknown meal type falls through to Unsorted" do
      assert MealTypeLabels.label("brunch", "el") == "Χωρίς κατηγορία"
    end
  end
end
