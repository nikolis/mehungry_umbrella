defmodule Mehungry.FoodData.Usda.Parser.Rules.ProcessingMethodRuleTest do
  use ExUnit.Case, async: true

  import Mehungry.ParserFixtures

  alias Mehungry.FoodData.Usda.Parser.Rules.{FrozenRule, RawRule}

  test "claims matching processing tokens and appends the method atom" do
    result = result([token(:food, "carrot"), token(:processing, "raw", segment: 1)])

    assert {:ok, applied} = RawRule.apply(result)
    assert applied.processing == [:raw]
    assert [_food, %{consumed: true}] = applied.tokens
  end

  test "ignores non-matching methods" do
    result = result([token(:processing, "raw", segment: 1)])
    assert {:ok, ^result} = FrozenRule.apply(result)
  end

  test "is idempotent (processing inference applied once)" do
    result = result([token(:processing, "raw", segment: 1)])
    {:ok, once} = RawRule.apply(result)
    {:ok, twice} = RawRule.apply(once)
    assert once == twice
    assert twice.processing == [:raw]
  end
end
