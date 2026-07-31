defmodule Mehungry.FoodData.Usda.Parser.Rules.BoneStateRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.BoneStateRule

  test "sets bone_state from the first unconsumed :bone_state token" do
    result = result([token(:bone_state, "boneless", segment: 1)])

    assert {:ok, applied} = BoneStateRule.apply(result)
    assert applied.bone_state == "boneless"
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "first wins and later bone-state tokens are still consumed" do
    result =
      result([
        token(:bone_state, "boneless", segment: 1),
        token(:bone_state, "lip on", segment: 2)
      ])

    assert {:ok, applied} = BoneStateRule.apply(result)
    assert applied.bone_state == "boneless"
    assert Enum.all?(applied.tokens, & &1.consumed)
  end

  test "leaves bone_state nil without a :bone_state token" do
    result = result([token(:processing, "raw")])
    assert {:ok, applied} = BoneStateRule.apply(result)
    assert applied.bone_state == nil
  end
end
