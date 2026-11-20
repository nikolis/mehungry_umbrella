defmodule Mehungry.Food.MealRolesTest do
  use ExUnit.Case, async: true

  alias Mehungry.Food.MealRoles

  test "the vocabulary is fixed and labelled" do
    assert MealRoles.all() ==
             ~w(breakfast main dinner soup salad side meze snack dessert drink pre_workout post_workout component)

    assert Enum.all?(MealRoles.all(), &(MealRoles.description(&1) != ""))
    assert MealRoles.label("meze") == "Meze"
    assert MealRoles.label("pre_workout") == "Pre-workout"
    assert MealRoles.valid?("main")
    refute MealRoles.valid?("appetizer")
  end

  test "slot_roles maps both planner labels and canonical meal types" do
    assert MealRoles.slot_roles("Dinner") == ~w(main dinner soup)
    assert MealRoles.slot_roles("lunch") == ~w(main soup)
    assert MealRoles.slot_roles("Breakfast") == ~w(breakfast)
    assert MealRoles.slot_roles("Afternoon Snack") == ~w(snack dessert drink)
    assert MealRoles.slot_roles(nil) == []
  end

  describe "fits_slot?/2" do
    test "a meze or side alone is not a lunch or dinner" do
      refute MealRoles.fits_slot?(["meze", "side"], "Dinner")
      refute MealRoles.fits_slot?(["salad"], "Lunch")
    end

    test "any meal-capable role fits lunch and dinner" do
      assert MealRoles.fits_slot?(["side", "main"], "Dinner")
      assert MealRoles.fits_slot?(["soup"], "Lunch")
    end

    test "a dinner dish fits Dinner but not Lunch" do
      assert MealRoles.fits_slot?(["dinner"], "Dinner")
      refute MealRoles.fits_slot?(["dinner"], "Lunch")
    end

    test "workout roles alone fill no planner slot" do
      refute MealRoles.fits_slot?(["pre_workout", "post_workout"], "Dinner")
      refute MealRoles.fits_slot?(["pre_workout"], "Morning Snack")
    end

    test "unclassified recipes always fit (rollout safety)" do
      assert MealRoles.fits_slot?([], "Dinner")
      assert MealRoles.fits_slot?(nil, "Breakfast")
    end

    test "a component never fits a meal slot" do
      refute MealRoles.fits_slot?(["component"], "Dinner")
      refute MealRoles.fits_slot?(["component"], "Morning Snack")
    end

    test "an unknown slot does not reject" do
      assert MealRoles.fits_slot?(["meze"], "Brunch")
    end
  end
end
