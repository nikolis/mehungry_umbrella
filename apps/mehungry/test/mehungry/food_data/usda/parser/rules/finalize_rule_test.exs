defmodule Mehungry.FoodData.Usda.Parser.Rules.FinalizeRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.FinalizeRule

  test "dedupes lists and rounds confidence" do
    result =
      result([],
        processing: [:raw, :raw, :frozen],
        processing_modifiers: ["dill", "dill"],
        confidence: 0.876543
      )

    assert {:ok, applied} = FinalizeRule.apply(result)
    assert applied.processing == [:raw, :frozen]
    assert applied.processing_modifiers == ["dill"]
    assert applied.confidence == 0.877
  end

  test "clamps confidence into [0.0, 1.0]" do
    assert {:ok, %{confidence: 1.0}} = FinalizeRule.apply(result([], confidence: 1.2))

    {:ok, low} = FinalizeRule.apply(result([], confidence: -0.5))
    assert low.confidence == 0.0
  end

  test "sweeps processing tokens no dedicated rule claimed" do
    result = result([token(:processing, "smoked", segment: 1)])

    assert {:ok, applied} = FinalizeRule.apply(result)
    assert applied.processing == [:smoked]
    assert Enum.all?(applied.tokens, & &1.consumed)
  end
end
