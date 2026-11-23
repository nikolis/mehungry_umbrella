defmodule Mehungry.Professionals.CalorieBandTest do
  @moduledoc "The calorie range a plan must land in — precedence and goal bands."
  use ExUnit.Case, async: true

  alias Mehungry.Professionals.CalorieBand

  describe "band/2 from TDEE and the goal type" do
    test "lose: 20% to 10% under TDEE" do
      assert CalorieBand.band(%{tdee_kcal: 1995, goal_type: "lose"}) ==
               %{min: 1596, max: 1796, aim: 1696, basis: :goal_lose}
    end

    test "maintain: within 10% of TDEE — also when the goal type is unset" do
      expected = %{min: 1796, max: 2195, aim: 1995, basis: :goal_maintain}

      assert CalorieBand.band(%{tdee_kcal: 1995, goal_type: "maintain"}) == expected
      assert CalorieBand.band(%{tdee_kcal: 1995, goal_type: nil}) == expected
      assert CalorieBand.band(%{tdee_kcal: 1995}) == expected
    end

    test "gain: 10% to 20% over TDEE" do
      assert CalorieBand.band(%{tdee_kcal: 1995, goal_type: "gain"}) ==
               %{min: 2195, max: 2394, aim: 2294, basis: :goal_gain}
    end
  end

  describe "band/2 precedence" do
    test "an explicit target wins: ±10% of it, the goal type is ignored" do
      assert CalorieBand.band(%{target_kcal: 1600, tdee_kcal: 1995, goal_type: "gain"}, 2600) ==
               %{min: 1440, max: 1760, aim: 1600, basis: :prescribed}
    end

    test "no intake figures: ±10% of the client's own target" do
      assert CalorieBand.band(%{goal_type: "lose"}, 2200) ==
               %{min: 1980, max: 2420, aim: 2200, basis: :self}

      assert CalorieBand.band(nil, 2200).basis == :self
    end

    test "nothing to aim at → nil" do
      assert CalorieBand.band(nil, nil) == nil
      assert CalorieBand.band(%{goal_type: "lose"}, nil) == nil
    end
  end

  test "goal_type vocabulary" do
    assert CalorieBand.goal_type_values() == ~w(lose maintain gain)
    assert CalorieBand.goal_type_label("lose") == "Lose weight"
    assert CalorieBand.goal_type_label(nil) == nil
  end
end
